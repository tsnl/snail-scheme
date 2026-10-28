(import
 (snail core base)
 (snail core io))

(: even? (-> I64 Bool))
(define (even? n)
  (if (= n 0) #t (odd? (- n 1))))

(: odd? (-> I64 Bool))
(define (odd? n)
  (if (= n 0) #f (even? (- n 1))))

(: apply-n (-> (-> I64 I64) I64 I64 I64))
(define (apply-n f n x)
  (if (= n 0) x (apply-n f (- n 1) (f x))))

(display (even? 10000001))
(newline)
(display (apply-n (lambda (x) (+ x 2)) 5000000 0))
(newline)
(display (length (iota 1000000)))
(newline)
