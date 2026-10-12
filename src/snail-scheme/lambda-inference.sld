;; Conditional summaries for optimization, not additional source contracts.
;; Flexible lambda arguments describe relationships in a successful invocation.
;; A caller may use a summary only after its arguments satisfy that summary.
(define-library (snail-scheme lambda-inference)
  (export make-lambda-inference inferred-type inferred-lambda-type known-lambda
          inferred-call-type inference-binding-type inference-procedure-type inference-assigned?)
  (import (scheme base) (scheme cxr) (snail-scheme types)
          (snail-scheme type-inference) (snail-scheme type-analysis) (snail-scheme wasm-intrinsics)
          (prefix (snail-scheme ir) ir:))
  (begin

    ;; ---- Shared definitions and independent lambda uses ----

    (define-record-type <inference>
      (make-state typing solver summaries pending active) inference?
      (typing state-typing) (solver state-solver)
      (summaries state-summaries set-state-summaries!)
      (pending state-pending set-state-pending!)
      (active state-active set-state-active!))

    (define (make-lambda-inference typing)
      (make-state typing (make-inference) '() '() '()))
    (define (lookup definition entries default)
      (let ((entry (assq definition entries))) (if entry (cdr entry) default)))
    (define (inference-binding-type definition state)
      (lookup definition (typing-declarations (state-typing state)) #f))
    (define (assigned? definition state)
      (memq definition (typing-assigned (state-typing state))))
    (define (inference-assigned? definition state) (assigned? definition state))

    (define (inference-procedure-type procedure state)
      (let find ((bindings (typing-bindings (state-typing state))))
        (cond ((null? bindings) #f)
              ((eq? procedure (cdar bindings)) (inference-binding-type (caar bindings) state))
              (else (find (cdr bindings))))))

    (define (known-lambda node state)
      (let resolve ((node node) (visited '()))
        (cond ((ir:lambda? node) node)
              ((ir:annotation? node) (resolve (ir:annotation-expression node) visited))
              ((ir:instantiation? node) (resolve (ir:instantiation-expression node) visited))
              ((and (ir:name? node) (not (assigned? (ir:name-definition node) state))
                    (not (memq (ir:name-definition node) visited)))
               (resolve (lookup (ir:name-definition node) (typing-bindings (state-typing state)) #f)
                        (cons (ir:name-definition node) visited)))
              (else #f))))

    (define (inferred-lambda-type node state)
      (or (lookup node (state-summaries state) #f)
          (lookup node (state-active state) #f)
          (infer-lambda node state)))

    ;; Reserve the recursive result before visiting the body. Every lambda
    ;; argument starts flexible; explicit All variables are never solver cells.
    (define (infer-lambda node state)
      (let* ((parameters (ir:lambda-parameters node))
             (arguments (map (lambda (parameter) (fresh-inference-variable! (state-solver state))) parameters))
             (result (fresh-inference-variable! (state-solver state)))
             (signature (cons '-> (append arguments (list result))))
             (active (state-active state)))
        (set-state-active! state (cons (cons node signature) active))
        (let* ((body (inferred-type (ir:lambda-body node) (map cons parameters arguments) state))
               (joined (if (unify-inference! result body) result '?))
               (summary (if (ir:lambda-opt-rest-parameter node) 'Procedure
                            (cons '-> (append arguments (list joined))))))
          (set-state-active! state active)
          (set-state-summaries! state (cons (cons node summary) (state-summaries state)))
          (set-state-pending! state (cons node (state-pending state)))
          (if (null? active) (generalize-group! state))
          (lookup node (state-summaries state) 'Procedure))))

    ;; A nested inference can share variables with an active recursive caller.
    ;; Generalizing it early would detach those equalities from later solves.
    ;; Reserve monomorphic summaries until the entire active group has settled.
    (define (generalize-group! state)
      (set-state-summaries!
       state (map (lambda (entry)
                    (if (memq (car entry) (state-pending state))
                        (cons (car entry) (generalize-inference (cdr entry))) entry))
                  (state-summaries state)))
      (set-state-pending! state '()))

    ;; ---- Expression guarantees after normal return ----

    (define (inferred-type node environment state)
      (cond ((ir:literal? node) (literal-type (ir:literal-value node)))
            ((ir:name? node) (inferred-name (ir:name-definition node) environment state))
            ((ir:lambda? node) (inferred-lambda-type node state))
            ((ir:annotation? node) (ir:annotation-type node))
            ((ir:instantiation? node)
             (guard (exception (else '?))
               (instantiate-type (inferred-type (ir:instantiation-expression node) environment state)
                                 (ir:instantiation-types node) (ir:instantiation-loc node))))
            ((ir:block? node) (inferred-sequence (ir:block-items node) environment state))
            ((ir:conditional? node)
             (join-inference (inferred-type (ir:conditional-consequent node) environment state)
                             (if (ir:conditional-opt-alternate node)
                                 (inferred-type (ir:conditional-opt-alternate node) environment state) 'Unspecified)))
            ((ir:application? node) (inferred-application node environment state))
            ((or (ir:assignment? node) (ir:type-declaration? node) (ir:record-schema? node)) 'Unspecified)
            (else '?)))

    (define (inferred-name definition environment state)
      (let ((declared (inference-binding-type definition state)))
        (cond ((assigned? definition state) (or declared '?))
              ((assq definition environment) => cdr)
              (declared declared)
              ((known-lambda (ir:make-name definition #f) state)
               => (lambda (node) (inferred-lambda-type node state)))
              (else
               (let ((initializer (lookup definition (typing-bindings (state-typing state)) #f)))
                 (if (ir:literal? initializer) (literal-type (ir:literal-value initializer)) '?))))))

    (define (inferred-sequence items environment state)
      (cond ((null? items) 'Unspecified)
            ((ir:value-binding? (car items))
             (let* ((binding (car items)) (definition (ir:value-binding-definition binding))
                    (type (or (inference-binding-type definition state)
                              (inferred-type (ir:value-binding-initializer binding) environment state))))
               (inferred-sequence (cdr items) (cons (cons definition type) environment) state)))
            ((null? (cdr items)) (inferred-type (car items) environment state))
            (else (inferred-type (car items) environment state)
                  (inferred-sequence (cdr items) environment state))))

    (define (join-inference left right)
      (cond ((or (eq? left '?) (eq? right '?)) '?)
            ((unify-inference! left right) (resolve-inference left))
            (else (type-union (resolve-inference left) (resolve-inference right)))))

    (define (inferred-application node environment state)
      (let* ((operator (ir:application-operator node))
             (arguments (map (lambda (node) (inferred-type node environment state)) (ir:application-operands node)))
             (primitive (and (ir:name? operator)
                             (memq (ir:name-definition operator) (typing-primitives (state-typing state)))
                             (ir:value-definition-name (ir:name-definition operator)))))
        (if primitive (primitive-result-type primitive arguments)
            (inferred-call-type (inferred-type operator environment state) arguments state))))

    ;; A failed inferred constraint loses precision. It does not become a new
    ;; diagnostic or a guard, and cannot change what dynamic Scheme accepts.
    (define (inferred-call-type signature arguments state)
      (let ((signature (instantiate-inference signature (state-solver state))))
        (if (and (arrow-type? signature)
                 (= (length arguments) (length (type-arguments signature)))
                 (constrain-arguments arguments (type-arguments signature)))
            (resolve-inference (type-result signature)) '?)))

    (define (constrain-arguments actuals formals)
      (or (null? actuals)
          (and (constrain-argument (car actuals) (car formals))
               (constrain-arguments (cdr actuals) (cdr formals)))))
    (define (constrain-argument actual formal)
      (let ((actual (resolve-inference actual)) (formal (resolve-inference formal)))
        (and (not (eq? actual '?))
             (or (type-subtype? actual formal) (unify-inference! actual formal)))))

    ;; ---- Primitive guarantees ----

    (define (all-types? types required)
      (or (null? types)
          (and (type-subtype? (resolve-inference (car types)) required)
               (all-types? (cdr types) required))))
    (define (constrain-each arguments type)
      (constrain-arguments arguments (map (lambda (argument) type) arguments)))

    (define (primitive-result-type name arguments)
      (cond ((memq name '(+ - * / quotient remainder modulo)) (numeric-result-type name arguments))
            ((memq name '(= < <= > >=))
             (constrain-each arguments 'Number) 'Boolean)
            ((memq name '(eq? eqv? equal? not boolean? number? exact-integer? integer? real? inexact?
                              string? symbol? char? pair? null? vector? bytevector? procedure?)) 'Boolean)
            ((find-intrinsic name (length arguments))
             => (lambda (entry)
                  (if (constrain-arguments arguments (intrinsic-domains entry)) (intrinsic-result entry) '?)))
            ((assq name primitive-signatures)
             => (lambda (entry)
                  (if (and (= (length arguments) (length (cadr entry)))
                           (constrain-arguments arguments (cadr entry))) (caddr entry) '?)))
            ((eq? name 'values) (if (= (length arguments) 1) (car arguments) '?))
            ((eq? name 'error) 'Never)
            (else '?)))

    (define (numeric-result-type name arguments)
      (cond ((memq name '(quotient remainder modulo))
             (if (constrain-each arguments 'ExactInteger) 'ExactInteger '?))
            ((and (not (eq? name '/)) (all-types? arguments 'ExactInteger)) 'ExactInteger)
            ((and (pair? arguments) (all-types? arguments 'InexactReal)) 'InexactReal)
            ((constrain-each arguments 'Number) 'Number)
            (else '?)))

    (define primitive-signatures
      '((cons (Any Any) Pair) (car (Pair) ?) (cdr (Pair) ?)
        (string-length (String) ExactInteger) (vector-length (Vector) ExactInteger)
        (bytevector-length (Bytevector) ExactInteger)
        (string-ref (String ExactInteger) Char) (vector-ref (Vector ExactInteger) ?)
        (bytevector-u8-ref (Bytevector ExactInteger) ExactInteger)
        (set-car! (Pair Any) Unspecified) (set-cdr! (Pair Any) Unspecified)
        (vector-set! (Vector ExactInteger Any) Unspecified)
        (string->symbol (String) Symbol) (symbol->string (Symbol) String)
        (char->integer (Char) ExactInteger) (integer->char (ExactInteger) Char))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-lambda-inference)
    (import (snail-scheme test-utils))
    (begin
      (define (test-independent-uses)
        (let* ((x (ir:make-value-definition 'x #f))
               (identity (ir:make-lambda (list x) #f (ir:make-block (list (ir:make-name x #f)) #f) #f))
               (state (make-lambda-inference (prepare-types '() '())))
               (summary (inferred-lambda-type identity state)))
          (expect (all-type? summary) #t)
          (expect (eq? (cadr (all-body summary)) (type-result (all-body summary))) #t)
          (expect (inferred-call-type summary '(String) state) 'String)
          (expect (inferred-call-type summary '(InexactReal) state) 'InexactReal)
          (expect (inferred-call-type summary '(?) state) '?)))

      (define (test-recursive-group reverse?)
        (let* ((f (ir:make-value-definition 'f #f)) (g (ir:make-value-definition 'g #f))
               (x (ir:make-value-definition 'x #f)) (y (ir:make-value-definition 'y #f))
               (predicate (ir:make-value-definition 'pair? #f))
               (f-body (ir:make-lambda (list x) #f
                                       (ir:make-application (ir:make-name g #f) (list (ir:make-name x #f)) #f) #f))
               (g-body (ir:make-lambda (list y) #f
                                       (ir:make-conditional
                                        (ir:make-application (ir:make-name predicate #f) (list (ir:make-name y #f)) #f)
                                        (ir:make-application (ir:make-name f #f) (list (ir:make-literal "string" #f)) #f)
                                        (ir:make-name y #f) #f) #f))
               (items (list (ir:make-value-binding f f-body #f) (ir:make-value-binding g g-body #f)))
               (state (make-lambda-inference (prepare-types items (list predicate)))))
          ;; An early generalized identity for either function would unsoundly
          ;; promise a Pair result, although this recursion returns a String.
          (inferred-lambda-type (if reverse? g-body f-body) state)
          (expect (inferred-lambda-type f-body state) '(-> String String))
          (expect (inferred-lambda-type g-body state) '(-> String String))
          (expect (inferred-call-type (inferred-lambda-type f-body state) '(Pair) state) '?)))

      (define (test-lambda-inference)
        (test-independent-uses)
        (test-recursive-group #f)
        (test-recursive-group #t))))))
