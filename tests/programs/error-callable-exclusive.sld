(import
 (snail core base))

(let ((function (ann (lambda (value) (+ value 1)) (impl (FnMut I64 -> I64)))))
  (function (function 1)))
