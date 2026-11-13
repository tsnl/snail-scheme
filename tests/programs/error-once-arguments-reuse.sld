(import
 (snail core base))

(define main
  (lambda ()
    (let ((work (once (lambda (value) (+ value 1)))))
      (work 1)
      (work 2))
    (unit)))
