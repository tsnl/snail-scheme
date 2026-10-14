(import (snail strict) (snail integer))
(define-overload expt (-> Integer I64 Integer) integer-power)
(define-overload expt (-> Integer Integer Integer) integer-expt)
(define (square value) (* value value))
(define (list . values) values)
(define (cadr values) (car (cdr values)))
(define (caddr values) (car (cdr (cdr values))))
(define (floor-real value)
  (let ((whole (truncate value))) (if (< value whole) (- whole 1.0) whole)))
(define (term-count digits)
  (integer-from-i64 (f64->i64 (floor-real (+ 2.0 (/ (i64->f64 digits) 14.181647462))))))
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

(define-extern input-i64 "benchmark" "input_i64" (-> I32 I64))
(define-extern expected-count "benchmark" "expected_count" (-> I64))
(define-extern expected-length "benchmark" "expected_length" (-> I64 I64))
(define-extern expected-character "benchmark" "expected_character" (-> I64 I64 Char))
(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))
(define-extern emit-character "benchmark" "emit_character" (-> Char Unit))
(define (expected-integer index)
  (let* ((count (expected-length index)) (text (make-string count)))
    (let loop ((at 0))
      (if (= at count) (integer-from-string text)
          (begin (string-set! text at (expected-character index at)) (loop (+ at 1)))))))
(define (same-integers? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (= (car left) (car right))
           (same-integers? (cdr left) (cdr right)))))
(define (same-rows? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (same-integers? (car left) (car right))
           (same-rows? (cdr left) (cdr right)))))
(define (write-integer value)
  (let ((text (integer->string value)))
    (let loop ((at 0))
      (unless (= at (string-length text))
        (emit-character (string-ref text at)) (loop (+ at 1))))))
(define (write-list render values)
  (emit-character (integer->char 40))
  (let loop ((tail values) (first? #t))
    (unless (null? tail)
      (unless first? (emit-character #\space))
      (render (car tail)) (loop (cdr tail) #f)))
  (emit-character (integer->char 41)))
(define (write-row row) (write-list write-integer row))
(define input0 (input-i64 (ann 0 I32)))
(define input1 (input-i64 (ann 1 I32)))
(define input2 (input-i64 (ann 2 I32)))
(: expected (List (List Integer)))
(define expected
  (let loop ((at 0))
    (if (= at (expected-count)) '() (cons (list (expected-integer at) (expected-integer (+ at 1)) (expected-integer (+ at 2))) (loop (+ at 3))))))
(define saved (ref (ann '() (List (List Integer)))))
(: bench (-> I64 I64))
(define (bench count)
  (if (< count 1) 0
      (let loop ((index 0) (result (ann '() (List (List Integer)))))
        (if (< index count)
            (loop (+ index 1) (pies (hide-i64 input0) (hide-i64 input1) (hide-i64 input2)))
            (begin (ref-set! saved result)
                   (if (same-rows? result expected) 1 0))))))
(: observe (-> Unit))
(define (observe)
  (write-list write-row (ref-get saved))
  (emit-character #\newline))
(unit)
