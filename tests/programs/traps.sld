(import
 (lofi base)
 (lofi io))

;; Integer arithmetic wraps; division by zero traps.
(display (* 4611686018427387904 2))
(newline)
(display (+ (ann 2147483647 I32) 1))
(newline)
(write-line "before")
(display (quotient 1 (- 1 1)))
(write-line "not reached")
