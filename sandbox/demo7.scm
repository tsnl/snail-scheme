((lambda (x y) x) 1 2)
((lambda (x y) y) 1 2)
((lambda (z)
  ((lambda (x y) z) 1 2)) 64)
((lambda (z)
  (begin
    (set! z 0)
    z)) 12345)

(define forty-two.1
  (call/cc 
    (lambda (return) 
      (begin
        (return 42)))))
(define forty-two.2 forty-two.1)

