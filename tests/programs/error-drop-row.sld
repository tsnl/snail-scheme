(import
 (snail core base)
 (owned handle))

;; Dropping a handle performs `log`, which this signature does not allow.
(define (release (handle Handle)) (→ Unit)
  (drop handle))
