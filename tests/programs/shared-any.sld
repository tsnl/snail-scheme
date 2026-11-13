(import
 (snail core base)
 (snail core io))

(define (main) (→ Unit) (! output-port)
  (let ((boxed
         (Any (let ((number 40)) (ann (lambda (x) (+ number x)) (Fn I64 → I64))))))
    (match (downcast (Fn I64 → I64) boxed)
      ((Some f) (display (f 2)) (newline))
      ((None) (display 0) (newline)))
    (match (downcast (Fn I64 → I64) boxed)
      ((Some f) (display (f 3)) (newline))
      ((None) (display 0) (newline))))
  (unit))
