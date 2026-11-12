(import
 (snail core base))

(define main
  (lambda ()
    (make-array 1 (once (lambda () (unit))))
    (unit)))
