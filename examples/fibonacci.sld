;; The smallest complete program: a typed recursive function and output.
(import
 (snail core base)
 (snail core io))

(define (fibonacci (n I64)) (→ I64)
  (if (< n 2) n (+ (fibonacci (- n 1)) (fibonacci (- n 2)))))

(display (fibonacci 30))
(newline)
