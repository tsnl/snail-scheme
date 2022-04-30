; ((lambda (x y) x) 1 2)
; ((lambda (x y) y) 1 2)
; ((lambda (z)
;   ((lambda (x y) z) 1 2)) 64)
; ((lambda (z)
;   (begin
;     (set! z 0)
;     z)) 12345)

(define weird-fn
  (call/cc 
    (lambda (return) 
      (begin
        return))))
(begin
  (weird-fn 42)
  43)

(define forty-two weird-fn)

