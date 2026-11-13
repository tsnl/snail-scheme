(import
 (snail core base))

(define main
  (lambda ()
    (type-convert (once (lambda () (unit))) Any)
    (unit)))
