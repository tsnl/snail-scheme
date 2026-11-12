(import
 (snail core base))

(define main
  (lambda ()
    (let ((function (ann (lambda (value) (+ value 1)) (Fn I64 → I64))))
      (function (function 1)))
    (unit)))
