;; Rank-one instantiation for shallow signatures. Rigid definition variables
;; never unify. Each use gets fresh lower/upper bounds, solved independently.
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
      (lower bounds-lower set-bounds-lower!)
      (upper bounds-upper set-bounds-upper!))

    (define (variable-bounds variable bounds)
      (cond ((null? bounds) #f)
            ((eq? variable (bounds-variable (car bounds))) (car bounds))
            (else (variable-bounds variable (cdr bounds)))))

    (define (add-lower! actual formal bounds)
      (let ((entry (variable-bounds formal bounds)))
        (cond ((eq? actual '?) #f)
              (entry (set-bounds-lower! entry (cons actual (bounds-lower entry))))
              ((union-type? formal) (union-lower! actual (cdr formal) bounds)))))

    ;; Concrete alternatives need no inference. A residual can determine one
    ;; variable; choosing between several variables would be arbitrary. Result
    ;; context may still solve those variables, after which validation decides.
    (define (union-lower! actual arms bounds)
      (let loop ((arms arms) (residual actual) (variables '()))
        (cond ((null? arms)
               (if (and (= (length variables) 1) (not (eq? residual 'Never)))
                   (add-lower! residual (car variables) bounds)))
              ((variable-bounds (car arms) bounds)
               (loop (cdr arms) residual (cons (car arms) variables)))
              (else (loop (cdr arms) (type-subtract residual (car arms)) variables)))))

    (define (add-upper! formal expected bounds)
      (let ((entry (variable-bounds formal bounds)))
        (cond ((or (not expected) (eq? expected '?)) #f)
              (entry (set-bounds-upper! entry (cons expected (bounds-upper entry))))
              ((union-type? formal)
               (for-each (lambda (arm) (add-upper! arm expected bounds)) (cdr formal))))))

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
        (for-each (lambda (actual formal) (add-lower! actual formal bounds))
                  arguments (type-arguments signature))
        (add-upper! (type-result signature) expected bounds)
        (let ((types (map (lambda (entry) (solve-bounds entry loc)) bounds)))
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
      (define (test-type-inference)
        (let* ((a (make-type-variable 'A))
               (identity (list 'All (list a) (list '-> a a)))
               (choose (list 'All (list a) (list '-> 'Boolean a a a))))
          (expect (infer-type-arguments identity '(String) #f #f) '(String))
          (expect (infer-type-arguments identity '(?) 'String #f) '(String))
          (expect (type-equal? (car (infer-type-arguments choose '(Boolean String False) #f #f))
                               '(U String False)) #t)
          (expect (instantiate-type identity '(String) #f) '(-> String String))
          (expect (instantiate-type identity (list a) #f) (list '-> a a))))))))
