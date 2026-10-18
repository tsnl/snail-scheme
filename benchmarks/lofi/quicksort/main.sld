;; Canonical bare Lofi. See migration.json for source provenance.

(import (lofi base))

(def cddr (lambda (xs.3) (cdr (cdr xs.3))))

(def length
  (lambda (xs.1)
    (((lambda () (begin (def loop.7 (lambda (xs.2 n.3) (if (null? xs.2) n.3 (loop.7 (cdr xs.2) (+ n.3 (ann 1 I64)))))) loop.7)))
      xs.1
      (ann 0 I64))))

(define-extern native-input-i64 "benchmark" "input_i64" (-> I32 I64))

(define-extern native-input-f64 "benchmark" "input_f64" (-> I32 F64))

(define-extern barrier "benchmark" "barrier" (-> Bool))

(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))

(define-extern hide-f64 "benchmark" "hide_f64" (-> F64 F64))

(define-extern native-count "benchmark" "count" (-> I64))

(define-extern native-vector-length "benchmark" "vector_length" (-> I32 I64))

(define-extern native-vector-i64 "benchmark" "vector_i64" (-> I32 I64 I64))

(define-extern native-expected-length "benchmark" "expected_length" (-> I64))

(define-extern native-expected-i64 "benchmark" "expected_i64" (-> I64 I64))

(def inexact (lambda (value.6) (i64->f64 value.6)))

(def exact (lambda (value.5) (f64->i64 value.5)))

(def values (lambda (value.4) value.4))

(def input-i64-vector
  (lambda (index.1)
    ((lambda (n.2) ((lambda (result.3) (((lambda () (begin (def loop.6 (lambda (i.10) (if (= i.10 n.2) result.3 (begin (vector-set! result.3 i.10 (native-vector-i64 index.1 i.10)) (loop.6 (+ i.10 (ann 1 I64))))))) loop.6))) (ann 0 I64))) (make-vector n.2 (ann 0 I64))))
      (native-vector-length index.1))))

(def same-expected-i64-vector?
  (lambda (source.4)
    (if (= (vector-length source.4) (native-expected-length))
      (((lambda () (begin (def loop.5 (lambda (i.9) ((lambda (value.3) (if value.3 value.3 (if (= (vector-ref source.4 i.9) (native-expected-i64 i.9)) (loop.5 (+ i.9 (ann 1 I64))) #f))) (= i.9 (vector-length source.4))))) loop.5)))
        (ann 0 I64))
      #f)))

(def same-input-i64-vector?
  (lambda (source.3 index)
    (if (= (vector-length source.3) (native-vector-length index))
      (((lambda () (begin (def loop.4 (lambda (i.8) ((lambda (value.2) (if value.2 value.2 (if (= (vector-ref source.3 i.8) (native-vector-i64 index i.8)) (loop.4 (+ i.8 (ann 1 I64))) #f))) (= i.8 (vector-length source.3))))) loop.4)))
        (ann 0 I64))
      #f)))

(def same-f64-list?
  (lambda (xs ys)
    (if (null? xs)
      (null? ys)
      (if (not (null? ys)) (if (= (car xs) (car ys)) (same-f64-list? (cdr xs) (cdr ys)) #f) #f))))

(def uninitialized-seed-set (-> (List F64) Unit) (lambda (state) (unreachable)))

(def uninitialized-seed-ref (-> (List F64)) (lambda () (unreachable)))

(def uninitialized-random-flonum (-> F64) (lambda () (unreachable)))

(def map-vector-elements
  (lambda (function source.2)
    ((lambda (n.1) (if (= n.1 (ann 0 I64)) (empty-vector) ((lambda (result.2) (((lambda () (begin (def loop.3 (lambda (i.7) (if (= i.7 n.1) result.2 (begin (vector-set! result.2 i.7 (function (vector-ref source.2 i.7))) (loop.3 (+ i.7 (ann 1 I64))))))) loop.3))) (ann 1 I64))) (make-vector n.1 (function (vector-ref source.2 (ann 0 I64)))))))
      (vector-length source.2))))

(def sorted-i64-vector?
  (lambda (source.1)
    (((lambda () (begin (def loop.2 (lambda (i.6) ((lambda (value.1) (if value.1 value.1 (if (<= (vector-ref source.1 (- i.6 (ann 1 I64))) (vector-ref source.1 i.6)) (loop.2 (+ i.6 (ann 1 I64))) #f))) (>= i.6 (vector-length source.1))))) loop.2)))
      (ann 1 I64))))

(def hide (lambda (count.5 x.1) (if (barrier) x.1 (unreachable))))

(def quick-1
  (lambda (v.2 less?.2)
    (begin
      (def helper
        (lambda (left.1 right.1)
          (if (< left.1 right.1)
            ((lambda (median) (if (< (- median left.1) (- right.1 median)) (begin (helper left.1 (- median (ann 1 I64))) (helper (+ median (ann 1 I64)) right.1)) (begin (helper (+ median (ann 1 I64)) right.1) (helper left.1 (- median (ann 1 I64))))))
              (partition v.2 left.1 right.1 less?.2))
            v.2)))
      (helper (ann 0 I64) (- (vector-length v.2) (ann 1 I64))))))

(def partition
  (lambda (v.1 left right less?.1)
    ((lambda (mid) (begin (def uploop (lambda (i.4) ((lambda (i.5) (if (if (< i.5 right) (less?.1 (vector-ref v.1 i.5) mid) #f) (uploop i.5) i.5)) (+ i.4 (ann 1 I64))))) (def downloop (lambda (j.2) ((lambda (j.3) (if (if (> j.3 left) (less?.1 mid (vector-ref v.1 j.3)) #f) (downloop j.3) j.3)) (- j.2 (ann 1 I64))))) (def ploop (lambda (i.2 j) ((lambda (i.3) ((lambda (j.1) ((lambda () ((lambda (tmp) (begin (vector-set! v.1 i.3 (vector-ref v.1 j.1)) (vector-set! v.1 j.1 tmp) (if (< i.3 j.1) (ploop i.3 j.1) (begin (vector-set! v.1 j.1 (vector-ref v.1 i.3)) (vector-set! v.1 i.3 (vector-ref v.1 right)) (vector-set! v.1 right tmp) i.3)))) (vector-ref v.1 i.3))))) (downloop j))) (uploop i.2)))) (ploop (- left (ann 1 I64)) right)))
      (vector-ref v.1 right))))

(def seed-set! (ref uninitialized-seed-set))

(def seed-ref (ref uninitialized-seed-ref))

(def random-flonum (ref uninitialized-random-flonum))

((lambda (norm m1 m2 a12 a13n a21 a23n seed) (begin (ref-set! random-flonum (lambda () ((lambda (seed.1) ((lambda (p1 p2) ((lambda (k1 k2 ignore1 ignore3) ((lambda (p1.1 p2.1 ignore2 ignore4) ((lambda (p1.2 p2.2) (begin (vector-set! seed.1 (ann 2 I64) p1.2) (vector-set! seed.1 (ann 5 I64) p2.2) (if (<= p1.2 p2.2) (* norm (+ (- p1.2 p2.2) m1)) (* norm (- p1.2 p2.2))))) (if (< p1.1 0.0) (+ p1.1 m1) p1.1) (if (< p2.1 0.0) (+ p2.1 m2) p2.1))) (- p1 (* k1 m1)) (- p2 (* k2 m2)) (vector-set! seed.1 (ann 1 I64) (vector-ref seed.1 (ann 2 I64))) (vector-set! seed.1 (ann 4 I64) (vector-ref seed.1 (ann 5 I64))))) (truncate (/ p1 m1)) (truncate (/ p2 m2)) (vector-set! seed.1 (ann 0 I64) (vector-ref seed.1 (ann 1 I64))) (vector-set! seed.1 (ann 3 I64) (vector-ref seed.1 (ann 4 I64))))) (- (* a12 (vector-ref seed.1 (ann 1 I64))) (* a13n (vector-ref seed.1 (ann 0 I64)))) (- (* a21 (vector-ref seed.1 (ann 5 I64))) (* a23n (vector-ref seed.1 (ann 3 I64)))))) (ref-get seed)))) (ref-set! seed-ref (lambda () (vector->list (ref-get seed)))) (ref-set! seed-set! (lambda (l) (ref-set! seed (list->vector l))))))
  2.328306549295728e-10
  4294967087.0
  4294944443.0
  1403580.0
  810728.0
  527612.0
  1370589.0
  (ref (vector 1.0 0.0 0.0 1.0 0.0 0.0)))

(def random (lambda (n) (exact (truncate (* (inexact n) ((ref-get random-flonum)))))))

(def setup-count (native-count))

(def input0 (hide setup-count (native-input-i64 (ann 0 I32))))

(def input1 (hide setup-count (native-input-i64 (ann 1 I32))))

(def less? (hide setup-count (ann (lambda (x y) (< x y)) (-> I64 I64 Bool))))

(def quicksort-input
  ((lambda (v) (((lambda () (begin (def loop.1 (lambda (i.1) (if (= i.1 input0) v (begin (vector-set! v i.1 (random input1)) (loop.1 (+ i.1 (ann 1 I64))))))) loop.1))) (ann 0 I64)))
    (ann (make-vector input0) (Vector I64))))

(def quicksort-probe (-> I64 I64)
  (lambda (count.4)
    ((lambda (source) ((lambda (result.1) ((lambda () (if (if (same-expected-i64-vector? result.1) (if (sorted-i64-vector? result.1) (if (same-input-i64-vector? source (ann 2 I32)) ((lambda (value) (if value value (not (vector-eq? result.1 source)))) (= (vector-length source) (ann 0 I64))) #f) #f) #f) (ann 1 I64) (ann 0 I64))))) (quick-1 (map-vector-elements values source) less?)))
      (input-i64-vector (ann 2 I32)))))

(def quicksort-rng-probe (-> I64 I64)
  (lambda (count.3) (if (same-expected-i64-vector? quicksort-input) (ann 1 I64) (ann 0 I64))))

(def quicksort-seed-probe (-> I64 I64)
  (lambda (count.2)
    (begin
      ((ref-get seed-set!) (list 1.0 0.0 0.0 1.0 0.0 0.0))
      (if (if (same-f64-list? ((ref-get seed-ref)) (vector->list (vector 1.0 0.0 0.0 1.0 0.0 0.0))) (= (random input1) (native-expected-i64 (ann 0 I64))) #f)
        (ann 1 I64)
        (ann 0 I64)))))

(def quicksort-sorted-probe (-> I64 I64)
  (lambda (count.1) (if (sorted-i64-vector? (input-i64-vector (ann 2 I32))) (ann 1 I64) (ann 0 I64))))

(def bench (-> I64 I64)
  (lambda (count)
    (if (sorted-i64-vector? (((lambda () (begin (def loop (lambda (i result) (if (< i count) (loop (+ i (ann 1 I64)) (quick-1 (map-vector-elements values quicksort-input) less?)) result))) loop))) (ann 0 I64) quicksort-input))
      (ann 1 I64)
      (ann 0 I64))))

(unit)
