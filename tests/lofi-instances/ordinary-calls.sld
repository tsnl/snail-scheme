(import (lofi primitive))
(define-extern record "instance.probe" "record" (-> I64 Unit))

;; ---- Ordinary calls preserve eager effects and monomorphic parameters ----

(def history (ref (ann 0 I64)))
(def mark (-> I64 Unit)
     (lambda (digit)
       (begin
         (ref-set! history (i64-add (i64-mul (ref-get history) (ann 10 I64)) digit))
         (record digit))))
(def observed (-> I64) (lambda () (ref-get history)))
(def invoke (-> I64 I64 I64)
     (lambda (value unused) (begin (mark (ann 4 I64)) value)))
(def named-result
     ((begin (mark (ann 3 I64)) invoke)
      (begin (mark (ann 1 I64)) (ann 42 I64))
      (begin (mark (ann 2 I64)) (ann 0 I64))))
((lambda (unused) (mark (ann 6 I64)))
 (begin (mark (ann 5 I64)) (unit)))
(def rest-result
     ((lambda (first . rest)
        (begin (mark (ann 8 I64)) (i64-add first (car rest))))
      (begin (mark (ann 7 I64)) (ann 20 I64))
      (ann 22 I64)))

;; Sequential let may generalize an initializer independently of call typing.
(def let-result
     (begin
       (let identity (lambda (value) value))
       (identity #t)
       (identity (ann 42 I64))))
(if (i64-eq named-result (ann 42 I64))
    (if (i64-eq rest-result (ann 42 I64))
        (if (i64-eq let-result (ann 42 I64))
            (if (i64-eq (observed) (ann 12345678 I64)) (ann 42 I64) (unreachable))
            (unreachable))
        (unreachable))
    (unreachable))
