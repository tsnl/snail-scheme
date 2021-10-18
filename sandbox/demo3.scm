; fibonacci

(define (fibonacci n)
  (if (or (= n 1) (= n 0))
    n
    (+
      (fibonacci (- n 1))
      (fibonacci (- n 2)))))

;;; TODO: fix me!
; (+ 1 2 3)
; (* 1 2 3 4 5)

(define a (fibonacci 25))
(define b 0)

(define (w x) 
  (begin 
    (set! b 42)
    (x a)))
(call/cc w)
