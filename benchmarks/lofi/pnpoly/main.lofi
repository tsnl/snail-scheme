;; Canonical bare Lofi. See migration.json for source provenance.

(import (lofi base))

(def cddr (lambda (xs.3) (cdr (cdr xs.3))))

(def length
  (lambda (xs.1)
    (((lambda () (begin (def loop.3 (lambda (xs.2 n.1) (if (null? xs.2) n.1 (loop.3 (cdr xs.2) (+ n.1 (ann 1 I64)))))) loop.3)))
      xs.1
      (ann 0 I64))))

(define-extern native-input-i64 "benchmark" "input_i64" (-> I32 I64))

(define-extern native-input-f64 "benchmark" "input_f64" (-> I32 F64))

(define-extern barrier "benchmark" "barrier" (-> Bool))

(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))

(define-extern hide-f64 "benchmark" "hide_f64" (-> F64 F64))

(def list (lambda elements elements))

(def append (lambda (xs ys) (if (null? xs) ys (cons (car xs) (append (cdr xs) ys)))))

(define-extern native-vector-length "benchmark" "vector_length" (-> I32 I64))

(define-extern native-vector-f64 "benchmark" "vector_f64" (-> I32 I64 F64))

(def input-vector
  (lambda (index)
    ((lambda (n) ((lambda (result.1) (begin (((lambda () (begin (def loop.2 (lambda (i.2) (if (< i.2 n) (begin (vector-set! result.1 i.2 (native-vector-f64 index i.2)) (loop.2 (+ i.2 (ann 1 I64))) (unit)) (unit)))) loop.2))) (ann 0 I64)) result.1)) (make-vector n 0.0)))
      (native-vector-length index))))

(def hide (lambda (count.2 x.1) (if (barrier) x.1 (unreachable))))

(def pt-in-poly2
  (lambda (xp.1 yp.1 x y)
    (((lambda () (begin (def loop.1 (lambda (c i.1 j) (if (< i.1 (ann 0 I64)) c (if ((lambda (value.2) (if value.2 value.2 (>= x (+ (vector-ref xp.1 i.1) (/ (* (- (vector-ref xp.1 j) (vector-ref xp.1 i.1)) (- y (vector-ref yp.1 i.1))) (- (vector-ref yp.1 j) (vector-ref yp.1 i.1))))))) (if ((lambda (value.1) (if value.1 value.1 (>= y (vector-ref yp.1 j)))) (> (vector-ref yp.1 i.1) y)) ((lambda (value) (if value value (>= y (vector-ref yp.1 i.1)))) (> (vector-ref yp.1 j) y)) #f)) (loop.1 c (- i.1 (ann 1 I64)) i.1) (loop.1 (not c) (- i.1 (ann 1 I64)) i.1))))) loop.1)))
      #f
      (- (vector-length xp.1) (ann 1 I64))
      (ann 0 I64))))

(def run
  (lambda (input1.1 input2)
    ((lambda (count.1 xp yp) (begin (if (pt-in-poly2 xp yp 0.5 0.5) (begin (ref-set! count.1 (+ (ref-get count.1) (ann 1 I64))) (unit)) (unit)) (if (pt-in-poly2 xp yp 0.5 1.5) (begin (ref-set! count.1 (+ (ref-get count.1) (ann 1 I64))) (unit)) (unit)) (if (pt-in-poly2 xp yp -0.5 1.5) (begin (ref-set! count.1 (+ (ref-get count.1) (ann 1 I64))) (unit)) (unit)) (if (pt-in-poly2 xp yp 0.75 2.25) (begin (ref-set! count.1 (+ (ref-get count.1) (ann 1 I64))) (unit)) (unit)) (if (pt-in-poly2 xp yp 0.0 2.01) (begin (ref-set! count.1 (+ (ref-get count.1) (ann 1 I64))) (unit)) (unit)) (if (pt-in-poly2 xp yp -0.5 2.5) (begin (ref-set! count.1 (+ (ref-get count.1) (ann 1 I64))) (unit)) (unit)) (if (pt-in-poly2 xp yp -1.0 -0.5) (begin (ref-set! count.1 (+ (ref-get count.1) (ann 1 I64))) (unit)) (unit)) (if (pt-in-poly2 xp yp -1.5 0.5) (begin (ref-set! count.1 (+ (ref-get count.1) (ann 1 I64))) (unit)) (unit)) (if (pt-in-poly2 xp yp -2.25 -1.0) (begin (ref-set! count.1 (+ (ref-get count.1) (ann 1 I64))) (unit)) (unit)) (if (pt-in-poly2 xp yp 0.5 -0.25) (begin (ref-set! count.1 (+ (ref-get count.1) (ann 1 I64))) (unit)) (unit)) (if (pt-in-poly2 xp yp 0.5 -1.25) (begin (ref-set! count.1 (+ (ref-get count.1) (ann 1 I64))) (unit)) (unit)) (if (pt-in-poly2 xp yp -0.5 -2.5) (begin (ref-set! count.1 (+ (ref-get count.1) (ann 1 I64))) (unit)) (unit)) (ref-get count.1)))
      (ref (ann 0 I64))
      (list->vector (vector->list input1.1))
      (list->vector (vector->list input2)))))

(def input0 (input-vector (ann 0 I32)))

(def input1 (input-vector (ann 1 I32)))

(def bench (-> I64 I64)
  (lambda (count)
    (((lambda () (begin (def loop (lambda (i result) (if (< i count) (loop (+ i (ann 1 I64)) (run (hide count input0) (hide count input1))) result))) loop)))
      (ann 0 I64)
      (ann 0 I64))))

(unit)
