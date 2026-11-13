(import
 (snail core base))

(define main
  (lambda ()
    (let ((work (once (lambda () (unit))))) (if #t (call-once work) (unit)) (call-once work))
    (unit)))
