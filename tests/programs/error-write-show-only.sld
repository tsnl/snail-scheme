(import
 (snail core base)
 (snail core io))

(struct Presented
  ())

(instance (Show (!) Presented)
  (define (show (value Presented)) (→ String)
    "presentation"))

(define main
  (lambda ()
    (write (Presented))
    (unit)))
