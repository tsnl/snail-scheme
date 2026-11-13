(import
 (snail core base)
 (snail core io))

(define (main) (→ Unit) (! output-port)
  (let ((boxed
         (type-convert (let ((number 40)) (ann (lambda (x) (+ number x)) (Fn I64 → I64))) Any)))
    (match (try-convert boxed (Fn I64 → I64))
      ((Ok f) (display (f 2)) (newline))
      ((Err _) (display 0) (newline)))
    (match (try-convert boxed (Fn I64 → I64))
      ((Ok f) (display (f 3)) (newline))
      ((Err _) (display 0) (newline))))
  (unit))
