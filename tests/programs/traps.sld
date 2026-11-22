(import
 (snail core base)
 (snail core io))

(define (main (out OutputPort)) (→ Unit) (! mut)
  ;; Integer arithmetic wraps; division by zero traps.
  (display out (* 4611686018427387904 2))
  (newline out)
  (display out (+ (ann 2147483647 I32) 1))
  (newline out)
  (write-line out "before")
  (display out (quotient 1 (- 1 1)))
  (write-line out "not reached")
  (unit))
