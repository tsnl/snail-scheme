;; Immutable concrete expression trees carry each specialization decision
;; directly to emission. No node-keyed evidence table or solver survives here.
(define-library (lofi compiler concrete)
  (export make-concrete-expression concrete-expression?
          concrete-source concrete-type concrete-detail concrete-children concrete-tail?
          make-concrete-conversion concrete-conversion? conversion-source conversion-from conversion-to conversion-child
          concrete-known-function)
  (import
   (scheme base)
   (only (lofi compiler ir) node-kind))
  (begin

    ;; ---- Settled expressions and explicit result adaptations ----

    ;; Types contain no solver variables. Children follow the source tree;
    ;; match arms retain (constructor-index parameter-ids expression) rows.
    (define-record-type <concrete-expression>
      (make-concrete-expression source type detail children tail?) concrete-expression?
      (source concrete-source)
      (type concrete-type)
      (detail concrete-detail)
      (children concrete-children)
      (tail? concrete-tail?))
    (define-record-type <concrete-conversion>
      (make-concrete-conversion source from to child) concrete-conversion?
      (source conversion-source)
      (from conversion-from)
      (to conversion-to)
      (child conversion-child))
    ;; Only a direct lambda initializer establishes its function identity.
    ;; Result adaptation preserves the identity; ordinary expression arms do not.
    (define (concrete-known-function expression)
      (cond ((concrete-conversion? expression) (concrete-known-function (conversion-child expression)))
            ((eq? (node-kind (concrete-source expression)) 'lambda) (concrete-detail expression))
            (else #f)))))
