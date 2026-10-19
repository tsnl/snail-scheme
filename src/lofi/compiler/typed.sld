;; Checking builds a provisional expression tree. Once all declarations settle,
;; freezing replaces expression type results with immutable rigid parameters.
(define-library (lofi compiler typed)
  (export make-typed-expression typed-expression? typed-source typed-type typed-constraints typed-detail typed-children
          make-typed-conversion typed-conversion? typed-conversion-source typed-conversion-from typed-conversion-to typed-conversion-child
          freeze-typed-expression)
  (import
   (scheme base)
   (scheme cxr)
   (lofi compiler types)
   (only (lofi compiler ir) node-kind value-binding-definition binding-scheme))
  (begin

    ;; ---- Immutable expression evidence ----

    (define-record-type <typed-expression>
      (make-typed-expression source type constraints detail children) typed-expression?
      (source typed-source)
      (type typed-type)
      (constraints typed-constraints)
      (detail typed-detail)
      (children typed-children))
    (define-record-type <typed-conversion>
      (make-typed-conversion source from to child) typed-conversion?
      (source typed-conversion-source)
      (from typed-conversion-from)
      (to typed-conversion-to)
      (child typed-conversion-child))

    ;; ---- Freeze after the solver has settled ----

    ;; This small renaming environment relates solver variable identities to
    ;; immutable parameters. It is threaded through construction, never keyed by
    ;; source nodes. Nominal records remain opaque identities. Scheme-variable
    ;; keys retain declaration identity; only existing binders grant polymorphism.
    (define (freeze-type type names)
      (let ((type (resolve type)))
        (cond ((hole? type)
               (let ((known (assq type names)))
                 (if known (values (cdr known) names)
                     (let ((parameter (fresh-rigid)))
                       (values parameter (cons (cons type parameter) names))))))
              ((pair? type)
               (let*-values (((first names) (freeze-type (car type) names))
                             ((rest names) (freeze-type (cdr type) names)))
                 (values (if (and (eq? first (car type)) (eq? rest (cdr type))) type (cons first rest)) names)))
              (else (values type names)))))
    (define (freeze-mapping mapping names)
      (if (null? mapping) (values '() names)
          (let*-values (((type names) (freeze-type (cdar mapping) names))
                        ((rest names) (freeze-mapping (cdr mapping) names)))
            (values (cons (cons (caar mapping) type) rest) names))))
    (define (freeze-detail expression names)
      (case (node-kind (typed-source expression))
        ((name instantiation)
         (let-values (((mapping names) (freeze-mapping (cadr (typed-detail expression)) names)))
           (values (list (car (typed-detail expression)) mapping) names)))
        ((bind)
         (let* ((binding (value-binding-definition (typed-source expression)))
                (variables (scheme-variables (binding-scheme binding))))
           (let-values (((mapping names) (freeze-mapping (map (lambda (variable) (cons variable variable)) variables) names)))
             (values (cons binding mapping) names))))
        ((literal) (values (typed-detail expression) names))
        (else (freeze-type (typed-detail expression) names))))
    (define (freeze-children children names)
      (if (null? children) (values '() names)
          (let*-values (((first names) (if (car children) (freeze-expression (car children) names) (values #f names)))
                        ((rest names) (freeze-children (cdr children) names)))
            (values (cons first rest) names))))
    (define (freeze-conversion expression names)
      (let*-values (((from names) (freeze-type (typed-conversion-from expression) names))
                    ((to names) (freeze-type (typed-conversion-to expression) names))
                    ((child names) (freeze-expression (typed-conversion-child expression) names)))
        (values (make-typed-conversion (typed-conversion-source expression) from to child) names)))
    (define (freeze-expression expression names)
      (if (typed-conversion? expression) (freeze-conversion expression names)
          (let*-values (((type names) (freeze-type (typed-type expression) names))
                        ((constraints names) (freeze-type (typed-constraints expression) names))
                        ((detail names) (freeze-detail expression names))
                        ((children names) (freeze-children (typed-children expression) names)))
            (values (make-typed-expression (typed-source expression) type constraints detail children) names))))
    (define (freeze-typed-expression expression)
      (let-values (((expression names) (freeze-expression expression '()))) expression)))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-typed)
    (import
     (lofi host test-utils)
     (only (lofi compiler ir) make-node))
    (begin
      (define (test-frozen-sharing)
        (let* ((hole (fresh-hole)) (alias (fresh-hole)) (nominal (vector 'nominal))
               (closed (list 'Data nominal 'I64)) (source (make-node 'literal #f '()))
               (left (make-typed-expression source (list 'Ref alias) '() #f '()))
               (right (make-typed-expression source (list 'Ref hole) '() #f '())))
          (unify! alias hole #f)
          (let* ((tree (freeze-typed-expression (make-typed-expression source closed '() #f (list left right))))
                 (first (cadr (typed-type (car (typed-children tree)))))
                 (second (cadr (typed-type (cadr (typed-children tree))))))
            (expect (eq? (typed-type tree) closed) #t)
            (expect (eq? (cadr (typed-type tree)) nominal) #t)
            (expect (and (rigid? first) (eq? first second)) #t)
            (unify! hole 'Bool #f)
            (expect (eq? (cadr (typed-type (car (typed-children tree)))) first) #t))))
      (define (test-typed)
        (run-test test-frozen-sharing))))))
