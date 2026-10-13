;; Rank-one instantiation for shallow signatures. Rigid definition variables
;; never unify. Each use collects immutable lower/upper bounds independently.
(define-library (snail-scheme type-inference)
  (export infer-type-arguments instantiate-type)
  (import (scheme base) (scheme cxr) (snail-scheme types))
  (begin

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
      (cond ((pair? (bounds-lower entry)) (join-lower-bounds (bounds-lower entry)))
            ((pair? (bounds-upper entry))
             (let loop ((types (bounds-upper entry)) (type 'Any))
               (if (null? types) type (loop (cdr types) (type-intersect type (car types))))))
            (else (type-error-at loc "cannot infer type argument; use inst" (bounds-variable entry)))))

    ;; The algebra expands Boolean and Number into complete unions. Retain a
    ;; named lower bound when its join is equivalent; explicit union bounds keep
    ;; their source form. Neither this join nor explicit inst promotes a subtype.
    (define (join-lower-bounds types)
      (let ((type (apply type-union types)))
        (cond ((not (union-type? type)) type)
              ((and (memq 'Boolean types) (type-subtype? type 'Boolean) (type-subtype? 'Boolean type)) 'Boolean)
              ((and (memq 'Number types) (type-subtype? type 'Number) (type-subtype? 'Number type)) 'Number)
              (else type))))

    (define (infer-type-arguments scheme arguments expected loc)
      (let* ((signature (all-body scheme))
             (bounds (map (lambda (variable) (make-bounds variable '() '())) (all-variables scheme))))
        (if (not (= (length arguments) (length (type-arguments signature))))
            (type-error-at loc "typed call has wrong arity" signature))
        (let* ((lower (argument-bounds arguments (type-arguments signature) bounds))
               (complete (add-upper (type-result signature) expected lower))
               (types (map (lambda (entry) (solve-bounds entry loc)) complete)))
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

      (define (test-scalar-lower-bounds)
        (let* ((a (make-type-variable 'A)) (identity (list 'All (list a) (list '-> a a))))
          (for-each (lambda (type) (expect (infer-type-arguments identity (list type) #f #f) (list type)))
                    '(Boolean Number True i32))
          (expect (join-lower-bounds '(Boolean False True)) 'Boolean)
          (expect (join-lower-bounds '(Number ExactInteger InexactReal Complex)) 'Number)
          (expect (type-equal? (join-lower-bounds '(False True)) '(U False True)) #t)
          (expect (type-equal? (join-lower-bounds '(ExactInteger InexactReal)) '(U ExactInteger InexactReal)) #t)
          (expect (type-equal? (join-lower-bounds '(String i32)) '(U String i32)) #t)
          (expect (instantiate-type identity '((U False True)) #f) '(-> (U False True) (U False True)))))

      (define (test-type-inference)
        (test-independent-bounds)
        (test-union-context)
        (test-scalar-lower-bounds)
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
