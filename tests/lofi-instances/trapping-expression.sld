(import (lofi primitive))
(define-extern record "instance.probe" "record" (-> I64 Unit))

;; A later failure preserves earlier effects and stops the following row.
(def history (ref (ann 0 I64)))
(def observed (-> I64) (lambda () (ref-get history)))
(def mark (-> I64 Unit)
     (lambda (digit)
       (begin
         (ref-set! history (i64-add (i64-mul (ref-get history) (ann 10 I64)) digit))
         (record digit))))
(def Three (typeclass (T)
                      (: first (-> T T)) (: second (-> T T)) (: third (-> T T))))
(def three-i64 (instance (Three I64)
                         (third (begin (mark (ann 1 I64)) (lambda (value) value)))
                         (first (begin (mark (ann 2 I64)) (unreachable)))
                         (second (begin (mark (ann 3 I64)) (lambda (value) value)))))
(ann 42 I64)
