; fibonacci

(define fibonacci 
  (lambda (n)
    (if (p/invoke or (p/invoke = n 1) (p/invoke = n 0))
      n
      (begin
        (p/invoke +
          (fibonacci (p/invoke - n 1))
          (fibonacci (p/invoke - n 2)))))))

;;; TODO: fix me!
; (+ 1 2 3)
; (* 1 2 3 4 5)

; (define a0 (fibonacci 30))
(define a0 (fibonacci 30))
; (p/invoke displayln a0)

; (define a1 (fibonacci 10))
; (display (format "~a\n" a1))
; (define a2 (fibonacci 30))
; (display (format "~a\n" a2))
; (define a3 (fibonacci 30))
; (display (format "~a\n" a3))
; (define a4 (fibonacci 30))

; (display (format "~a" a0))

; (define b 0)

; (define (w x) 
;   (begin 
;     (set! b 42)
;     (x a)))
; (call/cc w)

(p/invoke displayln a0)