(import
 (snail core base)
 (snail core io))

(record Presented
  ())

(instance (Show (!) Presented)
  (define (show (value Presented)) (→ String)
    "presentation"))

(define main
  (lambda ()
    (write (new Presented))
    (unit)))
