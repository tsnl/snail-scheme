(import
 (snail core base)
 (snail core io))

(record Point
  ((x I64)))

;; A path is checked as the read it is, where it is written.
(define (missing (point Point)) (→ I64) point::z)

(define (scalar (count I64)) (→ I64) count::x)

(define (main (out OutputPort)) (→ Unit)
  (unit))
