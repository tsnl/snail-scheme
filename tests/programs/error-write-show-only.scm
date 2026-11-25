(import
 (snail core base)
 (snail core io))

(record Presented
  ())

(instance (Show Presented)
  (define (show (value Presented)) (→ String)
    "presentation"))

(define (main (out OutputPort)) (→ Unit)
  (write out (new Presented))
  (unit))
