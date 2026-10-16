;; Canonical bare Lofi. See migration.json for source provenance.

(import (lofi base))

(def cddr (lambda (xs.2) (cdr (cdr xs.2))))

(def length
  (lambda (xs)
    (((lambda () (begin (def loop.4 (lambda (xs.1 n.4) (if (null? xs.1) n.4 (loop.4 (cdr xs.1) (+ n.4 (ann 1 I64)))))) loop.4)))
      xs
      (ann 0 I64))))

(define-extern native-input-i64 "benchmark" "input_i64" (-> I32 I64))

(define-extern native-input-f64 "benchmark" "input_f64" (-> I32 F64))

(define-extern barrier "benchmark" "barrier" (-> Bool))

(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))

(define-extern hide-f64 "benchmark" "hide_f64" (-> F64 F64))

(def hide (lambda (count.1 x.1) (hide-i64 x.1)))

(def create-x
  (lambda (n.3)
    (begin
      (def result.3 (make-vector n.3 (ann 0 I64)))
      (((lambda () (begin (def loop.3 (lambda (i.2) (if (>= i.2 n.3) result.3 (begin (vector-set! result.3 i.2 i.2) (loop.3 (+ i.2 (ann 1 I64))))))) loop.3)))
        (ann 0 I64)))))

(def create-y
  (lambda (x)
    ((lambda (n.2) ((lambda (result.2) ((lambda () (((lambda () (begin (def loop.2 (lambda (i.1) (if (< i.1 (ann 0 I64)) result.2 (begin (vector-set! result.2 i.1 (vector-ref x i.1)) (loop.2 (- i.1 (ann 1 I64))))))) loop.2))) (- n.2 (ann 1 I64)))))) (make-vector n.2 (ann 0 I64))))
      (vector-length x))))

(def my-try (lambda (n.1) (vector-length (create-y (create-x n.1)))))

(def go
  (lambda (m n)
    (((lambda () (begin (def loop.1 (lambda (repeat result.1) (if (> repeat (ann 0 I64)) (loop.1 (- repeat (ann 1 I64)) (my-try n)) result.1))) loop.1)))
      m
      (ann 0 I64))))

(def input0 (native-input-i64 (ann 0 I32)))

(def input1 (native-input-i64 (ann 1 I32)))

(def bench (-> I64 I64)
  (lambda (count)
    (((lambda () (begin (def loop (lambda (i result) (if (< i count) (loop (+ i (ann 1 I64)) (go (hide input0 input0) (hide input0 input1))) result))) loop)))
      (ann 0 I64)
      (ann 0 I64))))

(unit)
