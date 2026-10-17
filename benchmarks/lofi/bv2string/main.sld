;; Canonical bare Lofi. See migration.json for source provenance.

(import (lofi base) (lofi bytes))

(def cddr (lambda (xs.2) (cdr (cdr xs.2))))

(def length
  (lambda (xs)
    (((lambda () (begin (def loop.7 (lambda (xs.1 n.11) (if (null? xs.1) n.11 (loop.7 (cdr xs.1) (+ n.11 (ann 1 I64)))))) loop.7)))
      xs
      (ann 0 I64))))

(define-extern native-input-i64 "benchmark" "input_i64" (-> I32 I64))

(define-extern native-input-f64 "benchmark" "input_f64" (-> I32 F64))

(define-extern barrier "benchmark" "barrier" (-> Bool))

(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))

(define-extern hide-f64 "benchmark" "hide_f64" (-> F64 F64))

(def bv-same-bool? (-> Bool Bool Bool)
  (lambda (actual.1 expected.1) (if actual.1 expected.1 (not expected.1))))

(def bv-zero? (lambda (value.3) (= value.3 (ann 0 I64))))

(def bv-odd? (lambda (value.2) (not (= (remainder value.2 (ann 2 I64)) (ann 0 I64)))))

(def bv-round-quarter
  (lambda (value)
    ((lambda (whole part) (if ((lambda (value.1) (if value.1 value.1 (if (= part (ann 2 I64)) (bv-odd? whole) #f))) (> part (ann 2 I64))) (+ whole (ann 1 I64)) whole))
      (quotient value (ann 4 I64))
      (remainder value (ann 4 I64)))))

(define-extern bv-write-character "benchmark" "write_character" (-> Char Unit))

(def bv-display (-> String Unit)
  (lambda (text)
    (((lambda () (begin (def loop.6 (lambda (index) (if (= index (string-length text)) (unit) (begin (bv-write-character (string-ref text index)) (loop.6 (+ index (ann 1 I64))) (unit))))) loop.6)))
      (ann 0 I64))))

(def bv-newline (lambda () (bv-write-character #\newline)))

(def hide (lambda (count.1 x.1) (hide-i64 x.1)))

(def failed-tests (ref (ann (empty-list ) (List String))))

(def test (-> String Bool Bool Unit)
  (lambda (name actual expected)
    (if (bv-same-bool? actual expected)
      (unit)
      (begin
        (bv-display "******** FAILED TEST ******** ")
        (bv-display name)
        (bv-newline)
        (ref-set! failed-tests (cons name (ref-get failed-tests)))
        (unit)))))

(def string-bytevector-tests (-> I64 I64 Unit)
  (lambda (*random-stress-tests* *random-stress-test-max-size*)
    (begin
      (def test-roundtrip
        (lambda (bvec tostring tobvec)
          ((lambda (s1) ((lambda (b2) ((lambda (s2) ((lambda () (test "round trip of string conversion" (string=? s1 s2) #t)))) (tostring b2))) (tobvec s1)))
            (tostring bvec))))
      (def random
        ((lambda () (begin (def random14 (lambda (n.10) (begin (ref-set! x (remainder (+ (* a (ref-get x)) c) (+ m (ann 1 I64)))) (remainder (quotient (ref-get x) (ann 8 I64)) n.10)))) (def a (ann 701 I64)) (def x (ref (ann 1 I64))) (def c (ann 743483 I64)) (def m (ann 524287 I64)) (def loop.5 (lambda (q r n.9) (if (bv-zero? q) (remainder r n.9) (loop.5 (quotient q (ann 16384 I64)) (+ (* (ann 16384 I64) r) (random14 (ann 16384 I64))) n.9)))) (lambda (n.8) (if (< n.8 (ann 16384 I64)) (random14 n.8) (loop.5 (quotient n.8 (ann 16384 I64)) (random14 (ann 16384 I64)) n.8)))))
))
      (def random-bytevector
        (lambda (n.6)
          ((lambda (n.7) ((lambda (bv.2) ((lambda () (((lambda () (begin (def loop.4 (lambda (i.4) (if (= i.4 n.7) bv.2 (begin (bytevector-u8-set! bv.2 i.4 (random (ann 128 I64))) (loop.4 (+ i.4 (ann 1 I64))))))) loop.4))) (ann 0 I64))))) (make-bytevector n.7)))
            (random n.6))))
      (def random-bytevector2
        (lambda (n.3)
          ((lambda (n.4) ((lambda (n.5) ((lambda (bv.1) ((lambda () (((lambda () (begin (def loop.3 (lambda (i.3) (if (= i.3 n.5) bv.1 (begin (bytevector-u8-set! bv.1 i.3 (random (ann 128 I64))) (loop.3 (+ i.3 (ann 1 I64))))))) loop.3))) (ann 0 I64))))) (make-bytevector n.5))) (if (bv-odd? n.4) (+ n.4 (ann 1 I64)) n.4)))
            (random n.3))))
      (def random-bytevector4
        (lambda (n)
          ((lambda (n.1) ((lambda (n.2) ((lambda (bv) ((lambda () (((lambda () (begin (def loop.2 (lambda (i.2) (if (= i.2 n.2) bv (begin (bytevector-u8-set! bv i.2 (random (ann 128 I64))) (loop.2 (+ i.2 (ann 1 I64))))))) loop.2))) (ann 0 I64))))) (make-bytevector n.2))) (* (ann 4 I64) (bv-round-quarter n.1))))
            (random n))))
      (test-roundtrip (random-bytevector (ann 10 I64)) utf8->string string->utf8)
      (((lambda () (begin (def loop.1 (lambda (i.1) (if (= i.1 *random-stress-tests*) (unit) (begin (test-roundtrip (random-bytevector *random-stress-test-max-size*) utf8->string string->utf8) (loop.1 (+ i.1 (ann 1 I64))))))) loop.1)))
        (ann 0 I64)))))

(def input0 (native-input-i64 (ann 0 I32)))

(def input1 (native-input-i64 (ann 1 I32)))

(def input2 (native-input-i64 (ann 2 I32)))

(def bench (-> I64 I64)
  (lambda (count)
    (((lambda () (begin (def loop (lambda (i result) (if (< i count) (begin (string-bytevector-tests (hide count input0) (hide count input1)) (loop (+ i (ann 1 I64)) (length (ref-get failed-tests)))) (if (if (> i (ann 0 I64)) (= result input2) #f) (ann 1 I64) (ann 0 I64))))) loop)))
      (ann 0 I64)
      (ann 0 I64))))

(unit)
