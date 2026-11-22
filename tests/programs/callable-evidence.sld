(import
 (snail core base)
 (snail core io))

(define (twice (function (Fn I64 → I64)) (value I64)) (→ I64)
  (function (function value)))

(define (consume (function (Fn I64 → I64)) (value I64)) (→ I64)
  (function value))

(define (increment (value I64)) (→ I64) (+ value 1))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (write-line out (show (twice increment 10)))
  (write-line out (show (consume increment 20)))
  (write-line out (show (consume increment 30)))
  (write-line out (show (consume increment 40)))
  (write-line out (show (twice increment 50)))
  (write-line out (repr (map increment (list 60 70))))
  (unit))
