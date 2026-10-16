(import (chezscheme))
(define (square x) (* x x))
(define (integer-from-i64 value) value)
(define (integer-sqrt value) (let-values (((root remainder) (exact-integer-sqrt value))) root))
(define (term-count digits) (exact (floor (+ 2 (/ digits 14.181647462)))))
;;; PI -- Compute PI using bignums.

;; See http://mathworld.wolfram.com/Pi.html for the various algorithms.



(define (square-root x) (integer-sqrt x))

(define (quartic-root x)
  (square-root (square-root x)))


;;; Compute pi using the 'brent-salamin' method.

(define (pi-brent-salamin nb-digits)
  (let ((one (expt (integer-from-i64 10) nb-digits)))
    (let loop ((a one)
               (b (square-root (quotient (square one) (integer-from-i64 2))))
               (t (quotient one (integer-from-i64 4)))
               (x (integer-from-i64 1)))
      (if (= a b)
          (quotient (square (+ a b)) (* (integer-from-i64 4) t))
          (let ((new-a (quotient (+ a b) (integer-from-i64 2))))
            (loop new-a
                  (square-root (* a b))
                  (- t
                     (quotient
                      (* x (square (- new-a a)))
                      one))
                  (* (integer-from-i64 2) x)))))))

;;; Compute pi using the quadratically converging 'borwein' method.

(define (pi-borwein2 nb-digits)
  (let* ((one (expt (integer-from-i64 10) nb-digits))
         (one^2 (square one))
         (one^4 (square one^2))
         (sqrt2 (square-root (* one^2 (integer-from-i64 2))))
         (qurt2 (quartic-root (* one^4 (integer-from-i64 2)))))
    (let loop ((x (quotient
                   (* one (+ sqrt2 one))
                   (* (integer-from-i64 2) qurt2)))
               (y qurt2)
               (p (+ (* (integer-from-i64 2) one) sqrt2)))
      (let ((new-p (quotient (* p (+ x one))
                             (+ y one))))
        (if (= x one)
            new-p
            (let ((sqrt-x (square-root (* one x))))
              (loop (quotient
                     (* one (+ x one))
                     (* (integer-from-i64 2) sqrt-x))
                    (quotient
                     (* one (+ (* x y) one^2))
                     (* (+ y one) sqrt-x))
                    new-p)))))))

;;; Compute pi using the quartically converging 'borwein' method.

(define (pi-borwein4 nb-digits)
  (let* ((one (expt (integer-from-i64 10) nb-digits))
         (one^2 (square one))
         (one^4 (square one^2))
         (sqrt2 (square-root (* one^2 (integer-from-i64 2)))))
    (let loop ((y (- sqrt2 one))
               (a (- (* (integer-from-i64 6) one) (* (integer-from-i64 4) sqrt2)))
               (x (integer-from-i64 8)))
      (if (= y (integer-from-i64 0))
          (quotient one^2 a)
          (let* ((t1 (quartic-root (- one^4 (square (square y)))))
                 (t2 (quotient
                      (* one (- one t1))
                      (+ one t1)))
                 (t3 (quotient
                      (square (quotient (square (+ one t2)) one))
                      one))
                 (t4 (+ one
                        (+ t2
                           (quotient (square t2) one)))))
            (loop t2
                  (quotient
                   (- (* t3 a) (* x (* t2 t4)))
                   one)
                  (* (integer-from-i64 4) x)))))))

;;; Try it.

(define (pies n m s)
  (if (< m n)
      '()
      (let ((bs (pi-brent-salamin n))
            (b2 (pi-borwein2 n))
            (b4 (pi-borwein4 n)))
        (cons (list b2 (- bs b2) (- b4 b2))
              (pies (+ n s) m s)))))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (input2 (read))
         (input3 (read))
         (output (read))
         (s4 (number->string count))
         (s3 (number->string input3))
         (s2 (number->string input2))
         (s1 (number->string input1))
         (name "pi"))
    (run-r7rs-benchmark
     (string-append name ":" s1 ":" s2 ":" s3 ":" s4)
     count
     (lambda ()
       (pies (hide count input1)
             (hide count input2)
             (hide count input3)))
     (lambda (result) (equal? result output)))))
(define (hide r x)
  (call-with-values
   (lambda ()
     (values (vector values (lambda (x) x))
             (if (< r 100) 0 1)))
   (lambda (v i)
     ((vector-ref v i) x))))
(define (run-r7rs-benchmark name count thunk correct?)
  (let loop ((index 0) (result #f))
    (if (< index count) (loop (+ index 1) (thunk))
        (begin (unless (correct? result) (error 'benchmark "complete result differs" result))
               (write result) (newline)))))
(run-benchmark)
