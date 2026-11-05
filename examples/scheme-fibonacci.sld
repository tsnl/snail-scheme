#lang snail
;; The same layout reader with Scheme names and ordinary Scheme macros.
(import
 (scheme base))

define (fibonacci n)
  if (< n 2)
    n
    + (fibonacci (- n 1)) (fibonacci (- n 2))

display (fibonacci 25)
(newline)
display (map (lambda (x) (* x x)) (cons 1 (list 2 3)))
(newline)
let ((values (list 10 20 30)))
  display (car (cdr values))
  (newline)
