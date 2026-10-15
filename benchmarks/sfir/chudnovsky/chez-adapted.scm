(import (chezscheme))
(define (square x) (* x x))
(define (integer-from-i64 value) value)
(define (integer-sqrt value) (let-values (((root remainder) (exact-integer-sqrt value))) root))
(define (term-count digits) (exact (floor (+ 2 (/ digits 14.181647462)))))
;;; Compute digits of PI using a straightforward implementation of
;;; the Chudnovsky brothers algorithm; see
;;; http://www.craig-wood.com/nick/articles/pi-chudnovsky/



(define ch-A (integer-from-i64 13591409))
(define ch-B (integer-from-i64 545140134))
(define ch-C (integer-from-i64 640320))
(define ch-C^3 (expt (integer-from-i64 640320) (integer-from-i64 3)))
(define ch-D (integer-from-i64 12))

(define (ch-split a b)
  (if (= (integer-from-i64 1) (- b a))
      (let ((g (* (* (- (* (integer-from-i64 6) b) (integer-from-i64 5)) (- (* (integer-from-i64 2) b) (integer-from-i64 1))) (- (* (integer-from-i64 6) b) (integer-from-i64 1)))))
        (list g
              (quotient (* ch-C^3 (expt b (integer-from-i64 3))) (integer-from-i64 24))
              (* (* (expt (integer-from-i64 -1) b) g) (+ (* b ch-B) ch-A))))
      (let* ((mid (quotient (+ a b) (integer-from-i64 2)))
             (gpq1 (ch-split a mid))
             (gpq2 (ch-split mid b))
             (g1 (car gpq1)) (p1 (cadr gpq1)) (q1 (caddr gpq1))
             (g2 (car gpq2)) (p2 (cadr gpq2)) (q2 (caddr gpq2)))
        (list (* g1 g2)
              (* p1 p2)
              (+ (* q1 p2) (* q2 g1))))))



(define (pi digits)
  (let* ((num-terms (term-count digits))
         (sqrt-C (integer-sqrt (* ch-C (expt (integer-from-i64 100) digits)))))
    (let* ((gpq (ch-split (integer-from-i64 0) num-terms))
           (g (car gpq)) (p (cadr gpq)) (q (caddr gpq)))
      (quotient (* (* p ch-C) sqrt-C) (* ch-D (+ q (* p ch-A)))))))

(define (pies n m s)
  (if (< m n)
      '()
      (cons (pi n)
            (pies (+ n s) m s))))

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
         (name "chudnovsky"))
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
