;; The same program through (scheme base): Scheme names, Snail-Core types.
(import
 (scheme base))

(define (fibonacci n)
  (if (< n 2) n (+ (fibonacci (- n 1)) (fibonacci (- n 2)))))

(display (fibonacci 25))
(newline)
(display (map (lambda (x) (* x x)) (cons 1 (list 2 3))))
(newline)
(display (car (cdr (list 10 20 30))))
(newline)
