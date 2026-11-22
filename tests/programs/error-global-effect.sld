(import
 (snail core base))

;; A top-level value's initializer performs nothing: it runs once, whenever
;; the value is first read.
(record Count
  ((value I64)))

(define count (new Count (value 0)))

(define greeting
  (begin
    (set! (● count value) 1)
    1))
