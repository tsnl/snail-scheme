(import
 (snail core base))

(record Counter
  ((value I64)))

;; Every write names the Mut it was handed, before the place it writes.
(define (reset (counter Counter)) (→ Unit)
  (set! (● counter value) 0))
