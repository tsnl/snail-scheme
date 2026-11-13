(import
 (snail core base))

(define work (once (lambda () (unit))))

(define main
  (lambda ()
    (call-once work)
    (unit)))
