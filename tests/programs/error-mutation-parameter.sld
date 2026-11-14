(import
 (snail core base))

(record Counter
  ((value I64)))

;; Every write requires mut, including an ordinary field on a shared object.
(define (reset (counter Counter)) (→ Unit)
  (set! (● counter value) 0))
