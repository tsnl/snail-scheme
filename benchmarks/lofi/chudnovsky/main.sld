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
  (lambda (digits.1)
    (integer-from-i64 (f64->i64 (floor-real (+ 2.0 (/ (i64->f64 digits.1) 14.181647462)))))))

(def ch-A (integer-from-i64 (ann 13591409 I64)))

(def ch-B (integer-from-i64 (ann 545140134 I64)))

(def ch-C (integer-from-i64 (ann 640320 I64)))

(def ch-C^3 (expt (integer-from-i64 (ann 640320 I64)) (integer-from-i64 (ann 3 I64))))

(def ch-D (integer-from-i64 (ann 12 I64)))

(def ch-split
  (lambda (a b)
    (if (= (integer-from-i64 (ann 1 I64)) (- b a))
      ((lambda (g.1) (list g.1 (quotient (* ch-C^3 (expt b (integer-from-i64 (ann 3 I64)))) (integer-from-i64 (ann 24 I64))) (* (* (expt (integer-from-i64 (ann -1 I64)) b) g.1) (+ (* b ch-B) ch-A))))
        (*
          (*
            (- (* (integer-from-i64 (ann 6 I64)) b) (integer-from-i64 (ann 5 I64)))
            (- (* (integer-from-i64 (ann 2 I64)) b) (integer-from-i64 (ann 1 I64))))
          (- (* (integer-from-i64 (ann 6 I64)) b) (integer-from-i64 (ann 1 I64)))))
      ((lambda (mid) ((lambda (gpq1) ((lambda (gpq2) ((lambda (g1) ((lambda (p1) ((lambda (q1) ((lambda (g2) ((lambda (p2) ((lambda (q2) ((lambda () (list (* g1 g2) (* p1 p2) (+ (* q1 p2) (* q2 g1)))))) (caddr gpq2))) (cadr gpq2))) (car gpq2))) (caddr gpq1))) (cadr gpq1))) (car gpq1))) (ch-split mid b))) (ch-split a mid)))
        (quotient (+ a b) (integer-from-i64 (ann 2 I64)))))))

(def pi
  (lambda (digits)
    ((lambda (num-terms) ((lambda (sqrt-C) ((lambda () ((lambda (gpq) ((lambda (g) ((lambda (p) ((lambda (q) ((lambda () (quotient (* (* p ch-C) sqrt-C) (* ch-D (+ q (* p ch-A))))))) (caddr gpq))) (cadr gpq))) (car gpq))) (ch-split (integer-from-i64 (ann 0 I64)) num-terms))))) (integer-sqrt (* ch-C (expt (integer-from-i64 (ann 100 I64)) digits)))))
      (term-count digits))))

(def pies (lambda (n m s) (if (< m n) (empty-list ) (cons (pi n) (pies (+ n s) m s)))))

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

(def expected (List Integer)
  (((lambda () (begin (def loop.1 (lambda (at) (if (= at (expected-count)) (empty-list ) (cons (expected-integer at) (loop.1 (+ at (ann 1 I64))))))) loop.1)))
    (ann 0 I64)))

(def saved (ref (ann (empty-list ) (List Integer))))

(def bench (-> I64 I64)
  (lambda (count)
    (if (< count (ann 1 I64))
      (ann 0 I64)
      (((lambda () (begin (def loop (lambda (index result) (if (< index count) (loop (+ index (ann 1 I64)) (pies (hide-i64 input0) (hide-i64 input1) (hide-i64 input2))) (begin (ref-set! saved result) (if (same-integers? result expected) (ann 1 I64) (ann 0 I64)))))) loop)))
        (ann 0 I64)
        (ann (empty-list ) (List Integer))))))

(def observe (-> Unit)
  (lambda () (begin (write-list write-integer (ref-get saved)) (emit-character #\newline))))

(unit)
