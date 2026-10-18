;; Canonical bare Lofi. See migration.json for source provenance.

(import (lofi base) (lofi integer))

(define-overload expt (-> Integer I64 Integer) integer-power)

(define-overload expt (-> Integer Integer Integer) integer-expt)

(def square (lambda (value.2) (* value.2 value.2)))



(def cadr (lambda (values.2) (car (cdr values.2))))

(def caddr (lambda (values.1) (car (cdr (cdr values.1)))))

(def floor-real
  (lambda (value.1)
    ((lambda (whole) (if (< value.1 whole) (- whole 1.0) whole)) (truncate value.1))))

(def term-count
  (lambda (digits)
    (integer-from-i64 (f64->i64 (floor-real (+ 2.0 (/ (i64->f64 digits) 14.181647462)))))))

(def square-root (lambda (x.4) (integer-sqrt x.4)))

(def quartic-root (lambda (x.3) (square-root (square-root x.3))))

(def pi-brent-salamin
  (lambda (nb-digits.2)
    ((lambda (one.2) (((lambda () (begin (def loop.7 (lambda (a.1 b t x.2) (if (= a.1 b) (quotient (square (+ a.1 b)) (* (integer-from-i64 (ann 4 I64)) t)) ((lambda (new-a) (loop.7 new-a (square-root (* a.1 b)) (- t (quotient (* x.2 (square (- new-a a.1))) one.2)) (* (integer-from-i64 (ann 2 I64)) x.2))) (quotient (+ a.1 b) (integer-from-i64 (ann 2 I64))))))) loop.7))) one.2 (square-root (quotient (square one.2) (integer-from-i64 (ann 2 I64)))) (quotient one.2 (integer-from-i64 (ann 4 I64))) (integer-from-i64 (ann 1 I64))))
      (expt (integer-from-i64 (ann 10 I64)) nb-digits.2))))

(def pi-borwein2
  (lambda (nb-digits.1)
    ((lambda (one.1) ((lambda (one^2.1) ((lambda (one^4.1) ((lambda (sqrt2.1) ((lambda (qurt2) ((lambda () (((lambda () (begin (def loop.6 (lambda (x.1 y.1 p) ((lambda (new-p) (if (= x.1 one.1) new-p ((lambda (sqrt-x) (loop.6 (quotient (* one.1 (+ x.1 one.1)) (* (integer-from-i64 (ann 2 I64)) sqrt-x)) (quotient (* one.1 (+ (* x.1 y.1) one^2.1)) (* (+ y.1 one.1) sqrt-x)) new-p)) (square-root (* one.1 x.1))))) (quotient (* p (+ x.1 one.1)) (+ y.1 one.1))))) loop.6))) (quotient (* one.1 (+ sqrt2.1 one.1)) (* (integer-from-i64 (ann 2 I64)) qurt2)) qurt2 (+ (* (integer-from-i64 (ann 2 I64)) one.1) sqrt2.1))))) (quartic-root (* one^4.1 (integer-from-i64 (ann 2 I64)))))) (square-root (* one^2.1 (integer-from-i64 (ann 2 I64)))))) (square one^2.1))) (square one.1)))
      (expt (integer-from-i64 (ann 10 I64)) nb-digits.1))))

(def pi-borwein4
  (lambda (nb-digits)
    ((lambda (one) ((lambda (one^2) ((lambda (one^4) ((lambda (sqrt2) ((lambda () (((lambda () (begin (def loop.5 (lambda (y a x) (if (= y (integer-from-i64 (ann 0 I64))) (quotient one^2 a) ((lambda (t1) ((lambda (t2) ((lambda (t3) ((lambda (t4) ((lambda () (loop.5 t2 (quotient (- (* t3 a) (* x (* t2 t4))) one) (* (integer-from-i64 (ann 4 I64)) x))))) (+ one (+ t2 (quotient (square t2) one))))) (quotient (square (quotient (square (+ one t2)) one)) one))) (quotient (* one (- one t1)) (+ one t1)))) (quartic-root (- one^4 (square (square y)))))))) loop.5))) (- sqrt2 one) (- (* (integer-from-i64 (ann 6 I64)) one) (* (integer-from-i64 (ann 4 I64)) sqrt2)) (integer-from-i64 (ann 8 I64)))))) (square-root (* one^2 (integer-from-i64 (ann 2 I64)))))) (square one^2))) (square one)))
      (expt (integer-from-i64 (ann 10 I64)) nb-digits))))

(def pies
  (lambda (n m s)
    (if (< m n)
      (empty-list )
      ((lambda (bs b2 b4) (cons (list b2 (- bs b2) (- b4 b2)) (pies (+ n s) m s)))
        (pi-brent-salamin n)
        (pi-borwein2 n)
        (pi-borwein4 n)))))

(define-extern input-i64 "benchmark" "input_i64" (-> I32 I64))

(define-extern expected-count "benchmark" "expected_count" (-> I64))

(define-extern expected-length "benchmark" "expected_length" (-> I64 I64))

(define-extern expected-character "benchmark" "expected_character" (-> I64 I64 Char))

(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))

(define-extern emit-character "benchmark" "emit_character" (-> Char Unit))

(def expected-integer
  (lambda (index.1)
    ((lambda (count.1) ((lambda (text.1) ((lambda () (((lambda () (begin (def loop.4 (lambda (at.2) (if (= at.2 count.1) (integer-from-string text.1) (begin (string-set! text.1 at.2 (expected-character index.1 at.2)) (loop.4 (+ at.2 (ann 1 I64))))))) loop.4))) (ann 0 I64))))) (make-string count.1)))
      (expected-length index.1))))

(def same-integers?
  (lambda (left.1 right.1)
    (if (null? left.1)
      (null? right.1)
      (if (not (null? right.1))
        (if (= (car left.1) (car right.1)) (same-integers? (cdr left.1) (cdr right.1)) #f)
        #f))))

(def same-rows?
  (lambda (left right)
    (if (null? left)
      (null? right)
      (if (not (null? right))
        (if (same-integers? (car left) (car right)) (same-rows? (cdr left) (cdr right)) #f)
        #f))))

(def write-integer
  (lambda (value)
    ((lambda (text) (((lambda () (begin (def loop.3 (lambda (at.1) (if (= at.1 (string-length text)) (unit) (begin (emit-character (string-ref text at.1)) (loop.3 (+ at.1 (ann 1 I64))) (unit))))) loop.3))) (ann 0 I64)))
      (integer->string value))))

(def write-list
  (lambda (render values)
    (begin
      (emit-character (integer->char (ann 40 I64)))
      (((lambda () (begin (def loop.2 (lambda (tail first?) (if (null? tail) (unit) (begin (if first? (unit) (begin (emit-character #\space) (unit))) (render (car tail)) (loop.2 (cdr tail) #f) (unit))))) loop.2)))
        values
        #t)
      (emit-character (integer->char (ann 41 I64))))))

(def write-row (lambda (row) (write-list write-integer row)))

(def input0 (input-i64 (ann 0 I32)))

(def input1 (input-i64 (ann 1 I32)))

(def input2 (input-i64 (ann 2 I32)))

(def expected (List (List Integer))
  (((lambda () (begin (def loop.1 (lambda (at) (if (= at (expected-count)) (empty-list ) (cons (list (expected-integer at) (expected-integer (+ at (ann 1 I64))) (expected-integer (+ at (ann 2 I64)))) (loop.1 (+ at (ann 3 I64))))))) loop.1)))
    (ann 0 I64)))

(def saved (ref (ann (empty-list ) (List (List Integer)))))

(def bench (-> I64 I64)
  (lambda (count)
    (if (< count (ann 1 I64))
      (ann 0 I64)
      (((lambda () (begin (def loop (lambda (index result) (if (< index count) (loop (+ index (ann 1 I64)) (pies (hide-i64 input0) (hide-i64 input1) (hide-i64 input2))) (begin (ref-set! saved result) (if (same-rows? result expected) (ann 1 I64) (ann 0 I64)))))) loop)))
        (ann 0 I64)
        (ann (empty-list ) (List (List Integer)))))))

(def observe (-> Unit)
  (lambda () (begin (write-list write-row (ref-get saved)) (emit-character #\newline))))

(unit)
