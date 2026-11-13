(import
 (snail core base)
 (snail core io))

(struct Presented
  ())

(instance (Show (!) Presented)
  (define show (lambda (value) "presentation")))

(define main
  (lambda ()
    (write (Presented))
    (unit)))
