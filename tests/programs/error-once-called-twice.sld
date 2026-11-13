(import
 (snail core base)
 (snail core io))

(define main
  (lambda ()
    (let ((greet (once (lambda () (write-line "called once")))))
      (greet)
      (greet))
    (unit)))
