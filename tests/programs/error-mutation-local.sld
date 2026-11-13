(import
 (snail core base))

(struct Counter
  ((value I64)))

;; Freshness does not silently erase a write's effect.
(define (build) (→ Counter)
  (let ((counter (Counter 0)))
    (set! (● counter value) 1)
    counter))
