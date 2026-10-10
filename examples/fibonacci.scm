(import (scheme base) (scheme write) (scheme time))

(define (fib n)
  (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))

(define start (current-jiffy))
(define answer (fib 25))
(define elapsed (- (current-jiffy) start))
(display "fib(25) = ") (write answer) (newline)
(display "elapsed seconds = ") (write (/ elapsed (* 1.0 (jiffies-per-second)))) (newline)
