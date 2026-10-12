;; Monomorphization is an IR-to-IR optimization after original-body checking.
;; Copies use ordinary resolved nodes and fresh local identities. A call view
;; retains its evaluated original closure, so allocation identity and captures
;; belong to the original Scheme program, never to a specialized code address.
(define-library (snail-scheme specialize)
  (export specialization-enabled specialize-libraries
          specialized-definition specialized-source specialized-procedure specialized-arguments
          specialized-signature specialized-result specialized-representation specialized-captures specialized-generics specialized-scope
          specialized-substitutions)
  (import (scheme base) (scheme cxr) (snail-scheme types) (snail-scheme type-inference)
          (snail-scheme type-analysis) (snail-scheme lambda-inference)
          (snail-scheme wasm-representation)
          (prefix (snail-scheme ir) ir:) (prefix (snail-scheme library) library:))
  (begin

    ;; ---- Bounded worklist ----

    (define specialization-enabled (make-parameter #t))
    (define-record-type <specialized>
      (make-specialized definition source arguments signature substitutions captures procedure result representation generics scope)
      specialized?
      (definition specialized-definition) (source specialized-source)
      (arguments specialized-arguments) (signature specialized-signature)
      (substitutions specialized-substitutions)
      (captures specialized-captures)
      (procedure specialized-procedure set-specialized-procedure!)
      (result specialized-result set-specialized-result!)
      (representation specialized-representation set-specialized-representation!)
      (generics specialized-generics set-specialized-generics!) (scope specialized-scope))
    (define-record-type <work>
      (make-work inference entries pending instances scopes) work?
      (inference work-inference) (entries work-entries set-work-entries!)
      (pending work-pending set-work-pending!) (instances work-instances) (scopes work-scopes))

    (define (lookup identity entries default)
      (let ((entry (assq identity entries))) (if entry (cdr entry) default)))
    (define (concrete? type)
      (and (runtime-type? type) (not (memq type '(? Any Never))) (not (union-type? type))))
    (define (every? predicate items)
      (or (null? items) (and (predicate (car items)) (every? predicate (cdr items)))))

    (define (matching-entry source arguments signature substitutions captures entries)
      (cond ((null? entries) #f)
            ((and (eq? source (specialized-source (car entries)))
                  (type-equal? arguments (specialized-arguments (car entries)))
                  (type-equal? signature (specialized-signature (car entries)))
                  (type-equal? captures (specialized-captures (car entries)))
                  (type-equal? substitutions (specialized-substitutions (car entries)))) (car entries))
            (else (matching-entry source arguments signature substitutions captures (cdr entries)))))

    (define (copy-count source entries)
      (if (null? entries) 0
          (+ (if (eq? source (specialized-source (car entries))) 1 0)
             (copy-count source (cdr entries)))))

    ;; Reserve before inspecting the body: recursion refers to the same entry.
    ;; The fixed limits bound code growth; exceeding one preserves a generic call.
    (define (request-copy source arguments signature substitutions captures work)
      (let ((substitutions (body-substitutions source substitutions work)))
        (or (matching-entry source arguments signature substitutions captures (work-entries work))
            (and (< (length (work-entries work)) 256) (< (copy-count source (work-entries work)) 8)
                 (let* ((definition (ir:make-value-definition 'specialized (ir:lambda-loc source)))
                        (result (if signature (type-result signature) '?))
                        (entry (make-specialized definition source arguments signature substitutions captures #f result 'eqref '()
                                                 (lookup source (work-scopes work) #f))))
                   (set-work-entries! work (cons entry (work-entries work)))
                   (set-work-pending! work (append (work-pending work) (list entry))) entry)))))

    ;; Keep only binders used by this body's types, in source occurrence order.
    ;; Recursive requests cannot accumulate duplicate/irrelevant outer binders.
    (define (body-substitutions source substitutions work)
      (let collect ((variables (body-type-variables source #f work)) (seen '()) (result '()))
        (cond ((null? variables) (reverse result))
              ((memq (car variables) seen) (collect (cdr variables) seen result))
              (else (let ((entry (assq (car variables) substitutions)))
                      (collect (cdr variables) (cons (car variables) seen)
                               (if entry (cons entry result) result)))))))

    (define (body-type-variables node scope work)
      (let ((scope (if (ir:lambda? node) (lookup node (work-scopes work) scope) scope)))
        (append (cond ((ir:lambda? node)
                       (type-variables (all-body (inference-procedure-type node (work-inference work)))))
                      ((ir:name? node) (scope-binding-variables (ir:name-definition node) scope))
                      ((ir:annotation? node) (type-variables (ir:annotation-type node)))
                      ((ir:type-declaration? node) (type-variables (ir:type-declaration-type node)))
                      ((ir:instantiation? node) (apply append (map type-variables (ir:instantiation-types node))))
                      ((ir:application? node) (apply append (map type-variables (lookup node (work-instances work) '()))))
                      (else '()))
                (apply append (map (lambda (child) (body-type-variables child scope work)) (children node))))))

    (define (specialize-libraries libraries typing . checked)
      (let* ((work (make-work (make-lambda-inference typing) '() '() (if (null? checked) '() (car checked))
                              (if (or (null? checked) (null? (cdr checked))) '() (cadr checked))))
             (rewritten (map (lambda (library) (rewrite-library library work)) libraries)))
        (finish-copies work)
        (let ((entries (reverse (work-entries work))))
          (for-each (lambda (entry)
                      (set-specialized-representation! entry (type-representation (specialized-result entry)))) entries)
          (settle-results entries (typing-primitives typing))
          (cons rewritten entries))))

    (define (finish-copies work)
      (unless (null? (work-pending work))
        (let ((entry (car (work-pending work))))
          (set-work-pending! work (cdr (work-pending work)))
          (finish-copy entry work)
          (finish-copies work))))

    (define (finish-copy entry work)
      (let* ((source (specialized-source entry))
             (renames (map (lambda (definition)
                             (cons definition (ir:make-value-definition (ir:value-definition-name definition)
                                                                        (ir:value-definition-loc definition))))
                           (bound-definitions source)))
             (environment (append (map cons (ir:lambda-parameters source) (specialized-arguments entry))
                                  (specialized-captures entry)))
             (body (rewrite (ir:lambda-body source) environment renames (specialized-substitutions entry) work)))
        (set-specialized-procedure! entry
                                    (ir:make-lambda (map (lambda (definition) (rename definition renames))
                                                         (ir:lambda-parameters source)) #f (car body) (ir:lambda-loc source)))
        (unless (specialized-signature entry)
          (set-specialized-result! entry (cond ((function-type? (cdr body)) 'Procedure)
                                               ((runtime-type? (cdr body)) (cdr body)) (else '?))))))

    ;; ---- Ordinary resolved IR and lexical identities ----

    (define (children node)
      (cond ((ir:lambda? node) (list (ir:lambda-body node)))
            ((ir:block? node) (ir:block-items node))
            ((ir:application? node) (cons (ir:application-operator node) (ir:application-operands node)))
            ((ir:value-binding? node) (list (ir:value-binding-initializer node)))
            ((ir:conditional? node)
             (list (ir:conditional-test node) (ir:conditional-consequent node) (ir:conditional-opt-alternate node)))
            ((ir:annotation? node) (list (ir:annotation-expression node)))
            ((ir:instantiation? node) (list (ir:instantiation-expression node)))
            ((ir:assignment? node) (list (ir:assignment-target node) (ir:assignment-value node)))
            (else '())))

    (define (bound-definitions node)
      (append (cond ((ir:lambda? node)
                     (append (ir:lambda-parameters node)
                             (if (ir:lambda-opt-rest-parameter node) (list (ir:lambda-opt-rest-parameter node)) '())))
                    ((ir:value-binding? node) (list (ir:value-binding-definition node)))
                    (else '()))
              (apply append (map bound-definitions (children node)))))
    (define (rename definition renames) (lookup definition renames definition))
    (define (substitute type substitutions) (type-substitute type substitutions))

    (define (rewrite-library library work)
      (library:make-library (library:library-name library) (library:library-imports library)
                            (library:library-exports library) (library:library-dependencies library)
                            (car (rewrite-sequence (library:library-body library) '() '() '() work))
                            (library:library-loc library)))

    ;; The exhaustive copy keeps each node's lexical and evaluation contract
    ;; visible. There is no alternate expression language for concrete workers.
    (define (rewrite node environment renames substitutions work)
      (let ((state (work-inference work)))
        (cond ((ir:name? node)
               (cons (ir:make-name (rename (ir:name-definition node) renames) (ir:name-loc node))
                     (substitute (inferred-type node environment state) substitutions)))
              ((ir:literal? node) (cons node (literal-type (ir:literal-value node))))
              ((ir:lambda? node) (rewrite-lambda node environment renames substitutions work))
              ((ir:block? node)
               (let ((body (rewrite-sequence (ir:block-items node) environment renames substitutions work)))
                 (cons (ir:make-block (car body) (ir:block-loc node)) (cdr body))))
              ((ir:application? node) (rewrite-application node environment renames substitutions work))
              ((ir:conditional? node) (rewrite-conditional node environment renames substitutions work))
              ((ir:annotation? node)
               (let ((child (rewrite (ir:annotation-expression node) environment renames substitutions work))
                     (type (substitute (ir:annotation-type node) substitutions)))
                 (cons (ir:make-annotation (car child) type (ir:annotation-loc node)) type)))
              ((ir:instantiation? node)
               (let ((child (rewrite (ir:instantiation-expression node) environment renames substitutions work)))
                 (cons (ir:make-instantiation (car child) (map (lambda (type) (substitute type substitutions))
                                                               (ir:instantiation-types node)) (ir:instantiation-loc node))
                       (substitute (inferred-type node environment state) substitutions))))
              ((ir:assignment? node)
               (let ((value (rewrite (ir:assignment-value node) environment renames substitutions work)))
                 (cons (ir:make-assignment (ir:make-name (rename (ir:name-definition (ir:assignment-target node)) renames)
                                                         (ir:name-loc (ir:assignment-target node)))
                                           (car value) (ir:assignment-loc node)) 'Unspecified)))
              ((ir:type-declaration? node)
               (cons (ir:make-type-declaration (rename (ir:type-declaration-definition node) renames)
                                               (substitute (ir:type-declaration-type node) substitutions)
                                               (ir:type-declaration-loc node)) 'Unspecified))
              ((ir:record-schema? node) (cons (rewrite-record node renames substitutions) 'Unspecified))
              (else (cons node '?)))))

    (define (rewrite-lambda node environment renames substitutions work)
      (let* ((signature (inference-procedure-type node (work-inference work)))
             (arguments (if signature (type-arguments (all-body signature))
                            (map (lambda (parameter) '?) (ir:lambda-parameters node))))
             (body (rewrite (ir:lambda-body node) (append (map cons (ir:lambda-parameters node) arguments) environment)
                            renames substitutions work))
             (procedure (ir:make-lambda (map (lambda (definition) (rename definition renames)) (ir:lambda-parameters node))
                                        (and (ir:lambda-opt-rest-parameter node) (rename (ir:lambda-opt-rest-parameter node) renames))
                                        (car body) (ir:lambda-loc node))))
        (register-concrete-entry node procedure signature environment substitutions work)
        (cons procedure (inferred-lambda-type node (work-inference work)))))

    ;; A monomorphic declaration establishes these domains even at an unknown
    ;; call site. Its existing checked Scheme entry can bridge to the same copy.
    (define (register-concrete-entry source procedure signature environment substitutions work)
      (when (and (arrow-type? signature) (not (ir:lambda-opt-rest-parameter source))
                 (every? concrete? (type-arguments signature)))
        (let ((entry (request-copy source (type-arguments signature) signature substitutions
                                   (capture-types source environment (work-inference work)) work)))
          (when entry (set-specialized-generics! entry (cons procedure (specialized-generics entry)))))))

    (define (rewrite-record node renames substitutions)
      (ir:make-record-schema (rename (ir:record-schema-definition node) renames)
                             (rename (ir:record-schema-constructor node) renames)
                             (rename (ir:record-schema-predicate node) renames) (ir:record-schema-arguments node)
                             (map (lambda (field)
                                    (list (car field) (substitute (cadr field) substitutions)
                                          (rename (caddr field) renames)
                                          (and (cadddr field) (rename (cadddr field) renames))))
                                  (ir:record-schema-fields node)) (ir:record-schema-loc node)))

    (define (rewrite-sequence items environment renames substitutions work)
      (cond ((null? items) (cons '() 'Unspecified))
            ((ir:value-binding? (car items))
             (rewrite-binding (car items) (cdr items) environment renames substitutions work))
            (else
             (let* ((first (rewrite (car items) environment renames substitutions work))
                    (rest (rewrite-sequence (cdr items) environment renames substitutions work)))
               (cons (cons (car first) (car rest)) (if (null? (cdr items)) (cdr first) (cdr rest)))))))

    (define (rewrite-binding node rest environment renames substitutions work)
      (let* ((definition (ir:value-binding-definition node))
             (initializer (rewrite (ir:value-binding-initializer node) environment renames substitutions work))
             (type (or (inference-binding-type definition (work-inference work)) (cdr initializer)))
             (tail (rewrite-sequence rest (cons (cons definition type) environment) renames substitutions work)))
        (cons (cons (ir:make-value-binding (rename definition renames) (car initializer) (ir:value-binding-loc node))
                    (car tail)) (cdr tail))))

    (define (rewrite-conditional node environment renames substitutions work)
      (let* ((test (rewrite (ir:conditional-test node) environment renames substitutions work))
             (yes (rewrite (ir:conditional-consequent node) environment renames substitutions work))
             (no (if (ir:conditional-opt-alternate node)
                     (rewrite (ir:conditional-opt-alternate node) environment renames substitutions work)
                     (cons #f 'Unspecified))))
        (cons (ir:make-conditional (car test) (car yes) (car no) (ir:conditional-loc node))
              (type-union (cdr yes) (cdr no)))))

    ;; ---- Call discovery and concrete substitutions ----

    (define (call-instance type arguments loc)
      (guard (exception (else #f))
        (cond ((all-type? type)
               (let ((types (infer-type-arguments type arguments #f loc)))
                 (cons (instantiate-type type types loc) (map cons (all-variables type) types))))
              ((arrow-type? type) (cons type '()))
              (else #f))))

    (define (explicit-signature operator state)
      (cond ((ir:annotation? operator) (ir:annotation-type operator))
            ((ir:instantiation? operator) (inferred-type operator '() state))
            ((ir:name? operator) (inference-binding-type (ir:name-definition operator) state))
            (else #f)))

    ;; Source contracts can strengthen an argument after their ordinary guard.
    ;; Inferred-only domains must already be justified by the actual argument.
    (define (copy-domains arguments signature)
      (if (and signature (= (length arguments) (length (type-arguments signature))))
          (map (lambda (actual formal) (if (and (not (memq formal '(WasmI32 WasmF32))) (type-subtype? actual formal)) actual formal))
               arguments (type-arguments signature))
          arguments))

    ;; An explicit instantiated view supplies domains even when actual values
    ;; are dynamic. Its call guards establish those domains before the body.
    (define (source-instance declared view arguments loc)
      (or (and (all-type? declared) (arrow-type? view)
               (call-instance declared (type-arguments view) loc))
          (call-instance declared arguments loc)))

    (define (rewrite-application node environment renames substitutions work)
      (let* ((operands (map (lambda (node) (rewrite node environment renames substitutions work)) (ir:application-operands node)))
             (operator (rewrite (ir:application-operator node) environment renames substitutions work))
             (types (lookup node (work-instances work) #f))
             (types (and types (map (lambda (type) (substitute type substitutions)) types)))
             (operator-node (if types (ir:make-instantiation (car operator) types (ir:application-loc node)) (car operator)))
             (arguments (map cdr operands))
             (source (known-lambda (ir:application-operator node) (work-inference work)))
             (declared (and source (or (inference-procedure-type source (work-inference work))
                                       (explicit-signature (ir:application-operator node) (work-inference work)))))
             (view-type (explicit-signature (ir:application-operator node) (work-inference work)))
             (view-type (if (and types (all-type? view-type))
                            (instantiate-type (substitute view-type substitutions) types (ir:application-loc node)) view-type))
             (instance (and declared (source-instance (substitute declared substitutions)
                                                      (and view-type (substitute view-type substitutions)) arguments (ir:application-loc node))))
             (domains (copy-domains arguments (and instance (car instance))))
             (entry (and source (not (ir:lambda-opt-rest-parameter source))
                         (= (length arguments) (length (ir:lambda-parameters source))) (every? concrete? domains)
                         (or (not declared) instance)
                         (request-copy source domains (and instance (car instance))
                                       (append (if instance (cdr instance) '()) substitutions)
                                       (capture-types source environment (work-inference work)) work)))
             (view (if entry (ir:make-specialization operator-node (specialized-definition entry) (ir:application-loc node)) operator-node))
             (type (if instance (type-result (car instance))
                       (substitute (inferred-type node environment (work-inference work)) substitutions))))
        (cons (ir:make-application view (map car operands) (ir:application-loc node)) type)))

    ;; Capture facts are semantic types, never captured values. A body copied
    ;; outside its lexical visitor still needs the enclosing rigid/concrete
    ;; assumptions to check its annotations. Mutable captures keep only their
    ;; enforced declarations; storage remains the original closure's cells.
    (define (capture-types source environment state)
      (let ((bound (bound-definitions source)) (seen '()) (result '()))
        (define (visit node)
          (if (ir:name? node)
              (let* ((definition (ir:name-definition node)) (entry (assq definition environment)))
                (when (and entry (not (memq definition bound)) (not (memq definition seen))
                           (shallow-type? (cdr entry)) (not (memq (cdr entry) '(? Procedure)))
                           (not (inference-assigned? definition state)))
                  (set! seen (cons definition seen)) (set! result (cons entry result))))
              (for-each visit (children node))))
        (visit source) (reverse result)))

    ;; ---- Tail-compatible result representations ----

    (define (entry-for definition entries)
      (cond ((null? entries) #f)
            ((eq? definition (specialized-definition (car entries))) (car entries))
            (else (entry-for definition (cdr entries)))))

    ;; This monotone scan only widens. A fallback call or a deferred tail guard
    ;; needs the shared eqref ABI; a concrete worker can never leave a conversion
    ;; waiting above a tail call. Non-tail result checks remain ordinary code.
    (define (settle-results entries primitives)
      (let ((changed? #f))
        (for-each (lambda (entry)
                    (unless (or (eq? (specialized-representation entry) 'eqref)
                                (compatible-tail? (ir:lambda-body (specialized-procedure entry))
                                                  entry entries primitives (if (specialized-signature entry)
                                                                               (list (type-result (specialized-signature entry))) '())))
                      (set-specialized-representation! entry 'eqref) (set! changed? #t))) entries)
        (if changed? (settle-results entries primitives))))

    ;; The visitor may know less than conditional inference at a call. A source
    ;; contract guarantees these domains even then, so the selected tail entry
    ;; cannot be declined later. Inferred-only tail entries keep eqref results.
    (define (guaranteed-entry? entry)
      (and (specialized-signature entry)
           (every? (lambda (pair) (type-subtype? (car pair) (cdr pair)))
                   (map cons (type-arguments (specialized-signature entry)) (specialized-arguments entry)))))

    (define (compatible-tail? node caller entries primitives expected)
      (cond ((ir:block? node)
             (or (null? (ir:block-items node))
                 (compatible-tail? (car (reverse (ir:block-items node))) caller entries primitives expected)))
            ((ir:conditional? node)
             (and (compatible-tail? (ir:conditional-consequent node) caller entries primitives expected)
                  (or (not (ir:conditional-opt-alternate node))
                      (compatible-tail? (ir:conditional-opt-alternate node) caller entries primitives expected))))
            ((ir:annotation? node) (compatible-tail? (ir:annotation-expression node) caller entries primitives
                                                     (cons (ir:annotation-type node) expected)))
            ((ir:application? node)
             (let* ((operator (ir:application-operator node))
                    (callee (and (ir:specialization? operator) (entry-for (ir:specialization-definition operator) entries))))
               (if callee
                   (and (guaranteed-entry? callee)
                        (equal? (specialized-representation caller) (specialized-representation callee))
                        (every? (lambda (type) (type-subtype? (specialized-result callee) type)) expected))
                   ;; Primitive applications are leaves in the caller's Wasm
                   ;; frame. Any other tail target uses the generic protocol.
                   (and (ir:name? operator)
                        (memq (ir:name-definition operator) primitives)
                        (memq (ir:value-definition-name (ir:name-definition operator))
                              '(+ - * / = < <= > >= eq? eqv? cons car cdr
                                  procedure? number? exact-integer? null? pair?))))))
            (else #t))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-specialize)
    (import (snail-scheme test-utils))
    (begin
      (define (test-inferred-copies)
        (let* ((x (ir:make-value-definition 'x #f)) (id (ir:make-value-definition 'id #f))
               (unknown (ir:make-value-definition 'unknown #f))
               (source (ir:make-lambda (list x) #f (ir:make-name x #f) #f))
               (values (list (ir:make-literal 1 #f) (ir:make-literal 2 #f)
                             (ir:make-literal "text" #f) (ir:make-literal (string->number "1.5") #f)
                             (ir:make-name unknown #f)))
               (items (cons (ir:make-value-binding id source #f)
                            (map (lambda (value) (ir:make-application (ir:make-name id #f) (list value) #f)) values)))
               (library (library:make-library #f '() '() '() items #f))
               (result (specialize-libraries (list library) (prepare-types items '())))
               (calls (cdr (library:library-body (caar result))))
               (copies (cdr result)))
          (expect (length copies) 3)
          (expect (map specialized-representation copies) '(i64 (ref $text_object) f64))
          (expect (eq? (ir:specialization-definition (ir:application-operator (car calls)))
                       (ir:specialization-definition (ir:application-operator (cadr calls)))) #t)
          (expect (ir:name? (ir:application-operator (car (reverse calls)))) #t)
          (expect (eq? x (car (ir:lambda-parameters (specialized-procedure (car copies))))) #f)
          (expect (eq? id (ir:name-definition (ir:specialization-expression (ir:application-operator (car calls))))) #t)))

      (define (test-instance-keys)
        (let* ((a (make-type-variable 'A)) (unused (make-type-variable 'Unused))
               (x (ir:make-value-definition 'x #f)) (capture (ir:make-value-definition 'capture #f))
               (source (ir:make-lambda (list x) #f (ir:make-annotation (ir:make-name x #f) a #f) #f))
               (work (make-work (make-lambda-inference (prepare-types '() '())) '() '() '() '()))
               (first (request-copy source '(String) '(-> String String) (list (cons a 'String))
                                    (list (cons capture 'String)) work))
               (again (request-copy source '(String) '(-> String String)
                                    (list (cons unused 'ExactInteger) (cons a 'String) (cons a 'String))
                                    (list (cons capture 'String)) work))
               (different (request-copy source '(String) '(-> String String) (list (cons a 'String))
                                        (list (cons capture 'InexactReal)) work)))
          (expect (eq? first again) #t)
          (expect (eq? first different) #f)))

      (define (test-tail-result-contracts)
        (let* ((target (ir:make-value-definition 'target #f))
               (caller (ir:make-value-definition 'caller #f))
               (callee-body (ir:make-lambda '() #f (ir:make-literal 1 #f) #f))
               (callee (make-specialized target callee-body '() '(-> ExactInteger) '() '()
                                         callee-body 'ExactInteger 'i64 '() #f))
               (call (ir:make-application (ir:make-specialization (ir:make-name target #f) target #f) '() #f))
               (body (ir:make-lambda '() #f (ir:make-annotation call 'ExactInteger #f) #f))
               (entry (make-specialized caller body '() '(-> i32) '() '() body 'i32 'i64 '() #f)))
          ;; The inner annotation cannot erase the stricter enclosing contract.
          (settle-results (list entry callee) '())
          (expect (specialized-representation entry) 'eqref)
          (expect (specialized-representation callee) 'i64)))

      (define (test-specialize)
        (test-inferred-copies)
        (test-instance-keys)
        (test-tail-result-contracts))))))
