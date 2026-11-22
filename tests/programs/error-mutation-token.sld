(import
 (snail core base))

(record Counter
  ((value I64)))

;; What a write names first is a Mut, and nothing else will do.
(define (reset (counter Counter)) (→ Unit)
  (set! "please" (● counter value) 0))
