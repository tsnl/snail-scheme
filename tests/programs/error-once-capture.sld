(import
 (snail core base))

(define main
  (lambda ()
    (let* ((work (once (lambda () (unit)))) (twice (lambda () (call-once work)))) (twice))
    (unit)))
