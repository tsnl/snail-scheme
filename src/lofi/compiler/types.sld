;; Inference variables are private solver identities, never the universal Top
;; value type. Schemes quantify variables; emitted instances contain none.
(define-library (lofi compiler types)
  (export fresh-hole hole? hole-link set-hole-link! fresh-rigid rigid?
          fresh-variable variable? variable-rigid? resolve unify! type-equal? type-variables type-contains?
          substitute concrete-type? require-concrete type-datum strict-error
          make-scheme scheme? scheme-variables scheme-type scheme-constraints
          set-scheme-variables! set-scheme-type! set-scheme-constraints!
          instantiate generalize free-scheme-variables identity-union
          function-type function-type? function-domains function-rest function-result
          scalar-types subtype? join-types)
  (import
   (scheme base)
   (scheme cxr)
   (lofi compiler source))
  (begin

    ;; ---- Variables and equality constraints ----

    ;; Hole is unsolved compile-time information. A rigid binder is a different
    ;; variant: it can be substituted at instantiation, but never linked by inference.
    (define-record-type <hole>
      (make-hole id link) hole?
      (id hole-id)
      (link hole-link set-hole-link!))
    (define-record-type <rigid>
      (make-rigid id) rigid?
      (id rigid-id))
    (define next-variable 0)
    (define (next-variable-id)
      (let ((id next-variable)) (set! next-variable (+ id 1)) id))
    (define (fresh-hole) (make-hole (next-variable-id) #f))
    (define (fresh-rigid) (make-rigid (next-variable-id)))
    (define (fresh-variable . rigid)
      (if (and (pair? rigid) (car rigid)) (fresh-rigid) (fresh-hole)))
    (define (variable? type) (or (hole? type) (rigid? type)))
    (define variable-rigid? rigid?)
    (define (variable-id type) (if (hole? type) (hole-id type) (rigid-id type)))
    (define (resolve type)
      (if (and (hole? type) (hole-link type))
          (let ((root (resolve (hole-link type)))) (set-hole-link! type root) root) type))
    (define (type-equal? left right)
      (let ((left (resolve left)) (right (resolve right)))
        (or (eq? left right)
            (and (pair? left) (pair? right) (type-equal? (car left) (car right))
                 (type-equal? (cdr left) (cdr right))))))
    (define (unify! left right loc)
      (let ((left (resolve left)) (right (resolve right)))
        (cond ((eq? left right) #t)
              ((and (variable? left) (variable? right)
                    (not (variable-rigid? left)) (not (variable-rigid? right)))
               (if (< (variable-id left) (variable-id right))
                   (set-hole-link! right left) (set-hole-link! left right)))
              ((and (variable? left) (not (variable-rigid? left))) (bind-variable! left right loc))
              ((and (variable? right) (not (variable-rigid? right))) (bind-variable! right left loc))
              ((and (pair? left) (pair? right))
               (unify! (car left) (car right) loc) (unify! (cdr left) (cdr right) loc))
              (else (strict-error loc "type mismatch; cannot unify" left right)))))
    (define (bind-variable! variable type loc)
      (if (type-contains? type variable)
          (strict-error loc "occurs check: infinite type" variable type)
          (set-hole-link! variable type)))
    ;; These queries need one answer, rather than a collected variable set.
    (define (type-contains? type variable)
      (let ((type (resolve type)))
        (or (eq? type variable)
            (and (pair? type) (or (type-contains? (car type) variable)
                                  (type-contains? (cdr type) variable))))))
    (define (identity-union left right)
      (if (null? left) right
          (identity-union (cdr left) (if (memq (car left) right) right (cons (car left) right)))))
    (define (type-variables type)
      (let ((type (resolve type)))
        (cond ((variable? type) (list type))
              ((pair? type) (identity-union (type-variables (car type)) (type-variables (cdr type))))
              (else '()))))
    (define (substitute type substitutions)
      (let* ((type (resolve type)) (entry (assq type substitutions)))
        (cond (entry (cdr entry))
              ((pair? type) (cons (substitute (car type) substitutions) (substitute (cdr type) substitutions)))
              (else type))))

    ;; ---- Polymorphic binding schemes ----

    (define-record-type <scheme>
      (make-scheme variables type constraints) scheme?
      (variables scheme-variables set-scheme-variables!)
      (type scheme-type set-scheme-type!)
      (constraints scheme-constraints set-scheme-constraints!))
    (define (free-scheme-variables scheme)
      (let remove ((variables (type-variables (cons (scheme-type scheme) (scheme-constraints scheme)))))
        (cond ((null? variables) '())
              ((memq (car variables) (scheme-variables scheme)) (remove (cdr variables)))
              (else (cons (car variables) (remove (cdr variables)))))))
    (define (instantiate scheme)
      (let ((substitutions (map (lambda (variable) (cons variable (fresh-variable))) (scheme-variables scheme))))
        (values (substitute (scheme-type scheme) substitutions)
                (substitute (scheme-constraints scheme) substitutions) substitutions)))
    (define (generalize type constraints environment nonexpansive?)
      (make-scheme (if nonexpansive? (generalization-variables type constraints environment) '())
                   type constraints))
    ;; Closed results and expansive initializers cannot gain quantified holes.
    ;; Avoid scanning every enclosing scheme when there is nothing to generalize.
    (define (generalization-variables type constraints environment)
      (let ((candidates (generalizable (type-variables (cons type constraints)) '())))
        (if (null? candidates) '()
            (generalizable candidates (apply identity-unions (map free-scheme-variables environment))))))
    (define (identity-unions . lists)
      (if (null? lists) '() (identity-union (car lists) (apply identity-unions (cdr lists)))))
    (define (generalizable variables free)
      (cond ((null? variables) '())
            ((or (variable-rigid? (car variables)) (memq (car variables) free)) (generalizable (cdr variables) free))
            (else (cons (car variables) (generalizable (cdr variables) free)))))

    ;; ---- Concrete shape and explicit lattice boundaries ----

    (define scalar-types '(I32 I64 F32 F64 Bool Char Unit Top Never))
    (define (function-type domains rest result) (list 'Function domains rest result))
    (define (function-type? type) (let ((type (resolve type))) (and (pair? type) (eq? (car type) 'Function))))
    (define (function-domains type) (cadr (resolve type)))
    (define (function-rest type) (caddr (resolve type)))
    (define (function-result type) (cadddr (resolve type)))
    (define (concrete-type? type)
      (let ((type (resolve type)))
        (cond ((variable? type) #f)
              ((pair? type) (and (concrete-type? (car type)) (concrete-type? (cdr type))))
              (else #t))))
    (define (require-concrete type loc)
      (if (concrete-type? type) (substitute type '())
          (strict-error loc "unresolved concrete representation type" type)))
    ;; Mutable Ref and Vector are invariant. Container and function conversions are not
    ;; inferred here: equality preserves their concrete physical layout.
    (define (subtype? source target)
      (or (type-equal? source target) (eq? (resolve source) 'Never) (eq? (resolve target) 'Top)))
    (define (join-types left right loc)
      (cond ((eq? (resolve left) 'Never) right) ((eq? (resolve right) 'Never) left)
            (else (unify! left right loc) left)))

    ;; ---- Located diagnostics ----

    (define (type-datum type)
      (let ((type (resolve type)))
        (cond ((variable? type) (list (if (rigid? type) 'Rigid 'Hole) (variable-id type)))
              ((pair? type) (cons (type-datum (car type)) (type-datum (cdr type))))
              (else type))))
    (define (strict-error loc message . details)
      (apply error (string-append
                    (if (loc? loc) (string-append (loc-filename loc) ":" (number->string (loc-line loc))
                                                  ":" (number->string (loc-column loc)) ": ") "") message)
             (map type-datum details))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-types)
    (import
     (native test-utils))
    (begin
      (define (test-generalization)
        (let* ((hole (fresh-hole)) (other (fresh-hole)) (rigid (fresh-rigid))
               (type (function-type (list hole) #f rigid))
               (constraints (list (list 'Proof other)))
               (environment (list (make-scheme '() hole '()))))
          (expect (scheme-variables (generalize type constraints environment #t)) (list other))
          (expect (scheme-variables (generalize type constraints environment #f)) '())
          (expect (scheme-variables (generalize 'I32 '() environment #t)) '())
          (expect (scheme-variables (generalize rigid '() environment #t)) '())
          (expect (scheme-variables (generalize hole '() (list (make-scheme (list hole) hole '())) #t)) (list hole))
          (expect (scheme-variables (generalize hole '() (list (make-scheme '() 'I32 (list (list 'Proof hole)))) #t)) '())
          (expect (hole-link hole) #f) (expect (hole-link other) #f)
          (unify! hole 'I32 #f)
          (expect (scheme-variables (generalize hole '() environment #t)) '())))
      (define (test-types)
        (run-test test-generalization)
        (let ((hole (fresh-hole)) (rigid (fresh-rigid)))
          (expect (map variable? (list hole rigid 'Top)) '(#t #t #f))
          (expect (map hole? (list hole rigid 'Top)) '(#t #f #f))
          (expect (concrete-type? hole) #f)
          (expect (concrete-type? 'Top) #t)
          (unify! hole 'Top #f)
          (expect (resolve hole) 'Top))
        (let* ((older (fresh-variable)) (newer (fresh-variable)))
          (unify! newer older #f)
          (expect (eq? (resolve newer) older) #t))
        (let ((a (fresh-variable)) (b (fresh-variable)))
          (unify! a (list 'Ref b) #f) (unify! b 'I64 #f)
          (expect (require-concrete a #f) '(Ref I64)))
        (let ((a (fresh-variable)))
          (expect (guard (failure (else 'occurs)) (unify! a (list 'Ref a) #f)) 'occurs))
        (let ((a (fresh-variable #t)))
          (expect (guard (failure (else 'rigid)) (unify! a 'I64 #f)) 'rigid))
        (let* ((a (fresh-variable)) (type (function-type (list a) #f a))
               (scheme (generalize type '() '() #t)))
          (let-values (((first checks substitutions) (instantiate scheme))
                       ((second other mapping) (instantiate scheme)))
            (unify! (car (function-domains first)) 'I64 #f)
            (unify! (car (function-domains second)) 'Bool #f)
            (expect (function-result (require-concrete first #f)) 'I64)
            (expect (function-result (require-concrete second #f)) 'Bool)))
        (expect (subtype? '(Ref I64) '(Ref Top)) #f)
        (expect (join-types 'Never 'I64 #f) 'I64))))
   (else)))
