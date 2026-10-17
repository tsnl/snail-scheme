(import
 (lofi primitive))
(define-extern record "instance.probe" "record" (-> I64 Unit))
(def history (ref (ann 0 I64)))
(def mark (lambda (digit) (begin (ref-set! history (i64-add (i64-mul (ref-get history) (ann 10 I64)) digit)) (record digit))))
(def observed (-> I64) (lambda () (ref-get history)))

(mark (ann 1 I64))
(def self (if #t (ann 42 I64) self))
(def first (if #t self second))
(def second first)
(mark (ann 2 I64))
;; The computed closure captures a later local slot without reading it.
(def local
     (lambda ()
       (begin
         (def left
              (if #t
                  (lambda (n) (if (i64-eq n (ann 0 I64)) second (right (i64-sub n (ann 1 I64)))))
                  (lambda (n) (ann 0 I64))))
         (def right
              (lambda (n) (if (i64-eq n (ann 0 I64)) second (left (i64-sub n (ann 1 I64))))))
         (left (ann 10000 I64)))))
(if (i64-eq (local) (ann 42 I64)) (unit) (unreachable))
(mark (ann 3 I64))
(if (i64-eq (observed) (ann 123 I64)) (ann 42 I64) (unreachable))
