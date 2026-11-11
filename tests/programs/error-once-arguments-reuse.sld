(import
 (snail core base))

(let ((work (once (lambda (value) (+ value 1)))))
  (work 1)
  (work 2))
