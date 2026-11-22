(import
 (snail core base)
 (snail core io))

(define (main (out OutputPort)) (→ Unit)
  (let ((boxed
         (Any (let ((number 40)) (ann (lambda (x) (+ number x)) (Fn I64 → I64))))))
    (match (downcast (Fn I64 → I64) boxed)
      ((Some f) (display out (f 2)) (newline out))
      ((None) (display out 0) (newline out)))
    (match (downcast (Fn I64 → I64) boxed)
      ((Some f) (display out (f 3)) (newline out))
      ((None) (display out 0) (newline out))))
  (unit))
