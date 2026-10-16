;; Canonical bare Lofi. See migration.json for source provenance.

(import (lofi base))

(def cddr (lambda (xs.2) (cdr (cdr xs.2))))

(def length
  (lambda (xs)
    (((lambda () (begin (def loop.1 (lambda (xs.1 n.1) (if (null? xs.1) n.1 (loop.1 (cdr xs.1) (+ n.1 (ann 1 I64)))))) loop.1)))
      xs
      (ann 0 I64))))

(define-extern native-input-i64 "benchmark" "input_i64" (-> I32 I64))

(define-extern native-input-f64 "benchmark" "input_f64" (-> I32 F64))

(define-extern barrier "benchmark" "barrier" (-> Bool))

(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))

(define-extern hide-f64 "benchmark" "hide_f64" (-> F64 F64))

(def hide (lambda (count.1 x) (hide-f64 x)))

(def fibfp
  (lambda (n) (if (f64-lt n 2.0) n (f64-add (fibfp (f64-sub n 1.0)) (fibfp (f64-sub n 2.0))))))

(def input0 (native-input-f64 (ann 0 I32)))

(def bench (-> I64 F64)
  (lambda (count)
    (((lambda () (begin (def loop (lambda (i result) (if (< i count) (loop (+ i (ann 1 I64)) (fibfp (hide count input0))) result))) loop)))
      (ann 0 I64)
      0.0)))

(unit)
