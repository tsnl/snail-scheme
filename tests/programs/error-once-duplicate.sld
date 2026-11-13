(import
 (snail core base))

(define main
  (lambda ()
    (let ((work (once (lambda () (unit))))) (call-once work) (call-once work))
    (unit)))
