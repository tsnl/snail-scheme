; fibonacci

(define (fibonacci n)
  (if (or (= n 1) (= n 0))
    n
    (+
      (fibonacci (- n 1)
      (fibonacci (- n 2))))))

;;; TODO: fix me!
; (+ 1 2 3)
; (* 1 2 3 4 5)
(fibonacci 5)

(define (w x) (x 42))
(call/cc w)
