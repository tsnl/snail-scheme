(import
 (snail core base))

(let ((function (ann (lambda (value) (+ value 1)) (Fn I64 → I64))))
  (function (function 1)))
