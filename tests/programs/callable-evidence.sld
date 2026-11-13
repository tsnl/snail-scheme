(import
 (snail core base)
 (snail core io))

(define (twice (function (Fn I64 → I64)) (value I64)) (→ I64)
  (function (function value)))

(define (consume (function (FnOnce I64 → I64)) (value I64)) (→ I64)
  (function value))

(define (increment (value I64)) (→ I64) (+ value 1))

(define (main) (→ Unit) (! output-port)
  (write-line (show (twice increment 10)))
  (write-line (show (consume (once increment) 20)))
  (write-line (show (consume (once increment) 30)))
  (write-line (show (consume (once increment) 40)))
  (write-line (show (twice increment 50)))
  (write-line (repr (map increment (list 60 70))))
  (unit))
