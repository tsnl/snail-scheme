(import
 (snail core base)
 (snail core io))

(record Point
  ((x I64)))

;; `::` reads a field, so no parameter, local or pattern variable holds one.
(define (parameter (point::x I64)) (→ I64) 1)

(define (local (point Point)) (→ I64)
  (let ((point::x 2))
    3))

(define (pattern (point Point)) (→ I64)
  (match point
    ((Point x::y) 1)))

;; A path's first name must be bound.
(define (unbound (point Point)) (→ I64) pointt::x)

(define (main (out OutputPort)) (→ Unit)
  (unit))
