;; Rank-one instantiation for shallow signatures. Rigid definition variables
;; never unify. Each use collects immutable lower/upper bounds independently.
(define-library (snail-scheme type-inference)
  (export infer-type-arguments instantiate-type
          make-inference fresh-inference-variable! inference-variable? inference-variable-id
          resolve-inference unify-inference! generalize-inference instantiate-inference)
  (import (scheme base) (scheme cxr) (snail-scheme types))
  (begin

    ;; ---- Flexible inference variables ----

    ;; These are solver cells, deliberately distinct from rigid All identities.
    ;; Each inference session numbers its cells in deterministic traversal order.
    (define-record-type <inference-variable>
      (make-inference-variable id solution) inference-variable?
      (id inference-variable-id) (solution inference-solution set-inference-solution!))

    (define (make-inference) (vector 0))
    (define (fresh-inference-variable! inference)
      (let ((id (vector-ref inference 0)))
        (vector-set! inference 0 (+ id 1))
        (make-inference-variable id #f)))

    (define (resolve-inference type)
      (cond ((and (inference-variable? type) (inference-solution type))
             (resolve-inference (inference-solution type)))
            ((nominal-type? type) type)
            ((pair? type) (cons (resolve-inference (car type)) (resolve-inference (cdr type))))
            (else type)))

    (define (inference-occurs? variable type)
      (let ((type (resolve-inference type)))
        (or (eq? variable type)
            (and (pair? type) (not (nominal-type? type))
                 (or (inference-occurs? variable (car type))
                     (inference-occurs? variable (cdr type)))))))

    (define (solve-inference! variable type)
      (and (not (inference-occurs? variable type))
           (begin (set-inference-solution! variable type) #t)))

    ;; Variable-variable equality always chooses the lowest stable identifier.
    ;; A failed solve is an optimization miss; it never changes a rigid binder.
    (define (unify-inference! left right)
      (let ((left (resolve-inference left)) (right (resolve-inference right)))
        (cond ((eq? left right) #t)
              ((and (inference-variable? left) (inference-variable? right))
               (if (< (inference-variable-id left) (inference-variable-id right))
                   (solve-inference! right left) (solve-inference! left right)))
              ((inference-variable? left) (solve-inference! left right))
              ((inference-variable? right) (solve-inference! right left))
              ((or (nominal-type? left) (nominal-type? right)) (type-equal? left right))
              ((and (pair? left) (pair? right))
               (and (unify-inference! (car left) (car right))
                    (unify-inference! (cdr left) (cdr right))))
              (else (type-equal? left right)))))

    (define (generalize-inference type)
      (let ((substitutions '()))
        (define (replace type)
          (cond ((assq type substitutions) => cdr)
                ((inference-variable? type)
                 (let ((variable (make-type-variable (string->symbol
                                                      (string-append "t" (number->string (inference-variable-id type)))))))
                   (set! substitutions (cons (cons type variable) substitutions)) variable))
                ((nominal-type? type) type)
                ((pair? type) (cons (replace (car type)) (replace (cdr type))))
                (else type)))
        (let ((body (replace (resolve-inference type))))
          (clean-all-type (list 'All (map cdr (reverse substitutions)) body)))))

    (define (instantiate-inference type inference)
      (if (not (all-type? type)) type
          (type-substitute (all-body type)
                           (map (lambda (variable) (cons variable (fresh-inference-variable! inference)))
                                (all-variables type)))))

    ;; ---- Explicit instantiation ----

    (define (instantiate-type scheme arguments loc)
      (if (not (all-type? scheme)) (type-error-at loc "inst requires an All signature" scheme))
      (if (not (= (length arguments) (length (all-variables scheme))))
          (type-error-at loc "wrong number of type arguments" scheme))
      (type-substitute (all-body scheme) (map cons (all-variables scheme) arguments)))

    ;; ---- Constraints at one use ----

    (define-record-type <bounds>
      (make-bounds variable lower upper)
      bounds?
      (variable bounds-variable)
      (lower bounds-lower)
      (upper bounds-upper))

    (define (variable-bounds variable bounds)
      (cond ((null? bounds) #f)
            ((eq? variable (bounds-variable (car bounds))) (car bounds))
            (else (variable-bounds variable (cdr bounds)))))

    (define (replace-bounds entry bounds)
      (if (eq? (bounds-variable entry) (bounds-variable (car bounds)))
          (cons entry (cdr bounds))
          (cons (car bounds) (replace-bounds entry (cdr bounds)))))

    (define (add-lower actual formal bounds)
      (let ((entry (variable-bounds formal bounds)))
        (cond ((eq? actual '?) bounds)
              (entry (replace-bounds (make-bounds formal (cons actual (bounds-lower entry))
                                                  (bounds-upper entry)) bounds))
              ((union-type? formal) (union-lower actual (cdr formal) bounds))
              (else bounds))))

    ;; Concrete alternatives need no inference. A residual can determine one
    ;; variable; choosing between several variables would be arbitrary. Result
    ;; context may still solve those variables, after which validation decides.
    (define (union-lower actual arms bounds)
      (let loop ((arms arms) (residual actual) (variables '()))
        (cond ((null? arms)
               (if (and (= (length variables) 1) (not (eq? residual 'Never)))
                   (add-lower residual (car variables) bounds) bounds))
              ((variable-bounds (car arms) bounds)
               (loop (cdr arms) residual (cons (car arms) variables)))
              (else (loop (cdr arms) (type-subtract residual (car arms)) variables)))))

    (define (add-upper formal expected bounds)
      (let ((entry (variable-bounds formal bounds)))
        (cond ((or (not expected) (eq? expected '?)) bounds)
              (entry (replace-bounds (make-bounds formal (bounds-lower entry)
                                                  (cons expected (bounds-upper entry))) bounds))
              ((union-type? formal)
               (let loop ((arms (cdr formal)) (bounds bounds))
                 (if (null? arms) bounds
                     (loop (cdr arms) (add-upper (car arms) expected bounds)))))
              (else bounds))))

    (define (argument-bounds actuals formals bounds)
      (if (null? actuals) bounds
          (argument-bounds (cdr actuals) (cdr formals)
                           (add-lower (car actuals) (car formals) bounds))))

    (define (solve-bounds entry loc)
      (cond ((pair? (bounds-lower entry)) (apply type-union (bounds-lower entry)))
            ((pair? (bounds-upper entry))
             (let loop ((types (bounds-upper entry)) (type 'Any))
               (if (null? types) type (loop (cdr types) (type-intersect type (car types))))))
            (else (type-error-at loc "cannot infer type argument; use inst" (bounds-variable entry)))))

    (define (infer-type-arguments scheme arguments expected loc)
      (let* ((signature (all-body scheme))
             (bounds (map (lambda (variable) (make-bounds variable '() '())) (all-variables scheme))))
        (if (not (= (length arguments) (length (type-arguments signature))))
            (type-error-at loc "typed call has wrong arity" signature))
        (let* ((lower (argument-bounds arguments (type-arguments signature) bounds))
               (complete (add-upper (type-result signature) expected lower))
               (used (type-variables signature))
               (types (map (lambda (entry)
                             (if (memq (bounds-variable entry) used) (solve-bounds entry loc) 'Any)) complete)))
          (validate-instance (instantiate-type scheme types loc) arguments expected loc)
          types)))

    (define (validate-instance signature arguments expected loc)
      (for-each (lambda (actual formal)
                  (if (not (type-compatible? actual formal))
                      (type-error-at loc "type mismatch in polymorphic call" actual 'expected formal)))
                arguments (type-arguments signature))
      (if (and expected (not (type-compatible? (type-result signature) expected)))
          (type-error-at loc "type mismatch in polymorphic result" (type-result signature) 'expected expected)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-type-inference)
    (import (snail-scheme test-utils))
    (begin
      (define (test-independent-bounds)
        (let* ((a (make-type-variable 'A))
               (empty (list (make-bounds a '() '())))
               (left (add-lower 'String a empty))
               (right (add-upper a 'ExactInteger empty)))
          (expect (bounds-lower (car empty)) '())
          (expect (bounds-upper (car empty)) '())
          (expect (solve-bounds (car left) #f) 'String)
          (expect (solve-bounds (car right) #f) 'ExactInteger)))

      (define (test-union-context)
        (let* ((a (make-type-variable 'A)) (b (make-type-variable 'B))
               (union (type-union a b))
               (signature (list 'All (list a b) (list '-> union union))))
          (expect (infer-type-arguments signature '(String) 'String #f)
                  '(String String))))

      (define (test-type-inference)
        (let* ((inference (make-inference))
               (first (fresh-inference-variable! inference))
               (second (fresh-inference-variable! inference))
               (rigid (make-type-variable 'A)))
          (expect (unify-inference! second first) #t)
          (expect (eq? (resolve-inference second) first) #t)
          (expect (unify-inference! rigid 'String) #f)
          (expect (unify-inference! first (list '-> first 'String)) #f)
          (expect (unify-inference! first 'String) #t)
          (expect (resolve-inference second) 'String))
        (let* ((inference (make-inference))
               (argument (fresh-inference-variable! inference))
               (scheme (generalize-inference (list '-> argument argument)))
               (one (instantiate-inference scheme inference))
               (two (instantiate-inference scheme inference)))
          (expect (all-type? scheme) #t)
          (expect (eq? (cadr one) (caddr one)) #t)
          (expect (eq? (cadr one) (cadr two)) #f))
        (test-independent-bounds)
        (test-union-context)
        (let* ((a (make-type-variable 'A))
               (identity (list 'All (list a) (list '-> a a)))
               (choose (list 'All (list a) (list '-> 'Boolean a a a))))
          (expect (infer-type-arguments identity '(String) #f #f) '(String))
          (expect (infer-type-arguments identity '(?) 'String #f) '(String))
          (expect (infer-type-arguments identity (list a) #f #f) (list a))
          (expect (type-equal? (car (infer-type-arguments choose '(Boolean String False) #f #f))
                               '(U String False)) #t)
          (expect (instantiate-type identity '(String) #f) '(-> String String))
          (expect (instantiate-type identity (list a) #f) (list '-> a a))))))))
