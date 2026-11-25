(import
 (snail core base)
 (snail core io))

(define (even? (n I64)) (→ Bool)
  (if (= n 0) #t (odd? (- n 1))))

(define (odd? (n I64)) (→ Bool)
  (if (= n 0) #f (even? (- n 1))))

(define (apply-n (f (Fn I64 → I64)) (n I64) (x I64)) (→ I64)
  (if (= n 0) x (apply-n f (- n 1) (f x))))

(record Log
  ((digits I64)))

(define (mark! (log Log) (digit I64) (value I64)) (→ I64)
  (set! (● log digits) (+ (* 10 (● log digits)) digit))
  value)

(define (swap (log Log) (n I64) (a I64) (b I64)) (→ I64)
  (if (= n 0) (+ (* 10 a) b)
      (swap log (- n 1) (mark! log 1 b) (mark! log 2 a))))

;; The recursive closure is reached through an alias. Its captures survive
;; a branch whose only incoming argument is the closure itself.
(define (captured (log Log)) (→ I64)
  (let again ()
    (let ((self again))
      (if (> (● log digits) 12) (● log digits)
          (begin (mark! log 1 0) (self))))))

(define (main (out OutputPort)) (→ Unit)
  (let ((log (new Log (digits 0))))
    (write-line out (show (swap log 3 2 7)))
    (write-line out (show (● log digits))))
  (write-line out (show (captured (new Log (digits 0)))))
  (display out (even? 10000001))
  (newline out)
  (display out (apply-n (lambda (x) (+ x 2)) 5000000 0))
  (newline out)
  (display out (length (iota 1000000)))
  (newline out)
  (unit))
