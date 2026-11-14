(import
 (snail core base))

(record Counter
  ((value I64)))

;; Freshness does not silently erase a write's effect.
(define (build) (→ Counter)
  (let ((counter (new Counter (value 0))))
    (set! (● counter value) 1)
    counter))
