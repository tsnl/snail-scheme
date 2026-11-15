(import
 (snail core base)
 (snail core io))

(define (twice (function (Fn I64 → I64)) (value I64)) (→ I64)
  (function (function value)))

(define (consume (function (Fn I64 → I64)) (value I64)) (→ I64)
  (function value))

(define (increment (value I64)) (→ I64) (+ value 1))

(define (main) (→ Unit) (! output-port)
  (write-line (show (twice increment 10)))
  (write-line (show (consume increment 20)))
  (write-line (show (consume increment 30)))
  (write-line (show (consume increment 40)))
  (write-line (show (twice increment 50)))
  (write-line (repr (map increment (list 60 70))))
  (unit))
