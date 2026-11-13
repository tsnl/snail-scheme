(import
 (snail core base))

(define main
  (lambda ()
    (make-vector 1 (once (lambda () (unit))))
    (unit)))
