;; Canonical bare Lofi. See migration.json for source provenance.

(import (lofi base) (lofi io) (lofi datum) (lofi read))

(def cddr (lambda (xs.2) (cdr (cdr xs.2))))

(def length
  (lambda (xs)
    (((lambda () (begin (def loop.2 (lambda (xs.1 n) (if (null? xs.1) n (loop.2 (cdr xs.1) (+ n (ann 1 I64)))))) loop.2)))
      xs
      (ann 0 I64))))

(define-extern native-input-i64 "benchmark" "input_i64" (-> I32 I64))

(define-extern native-input-f64 "benchmark" "input_f64" (-> I32 F64))

(define-extern barrier "benchmark" "barrier" (-> Bool))

(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))

(define-extern hide-f64 "benchmark" "hide_f64" (-> F64 F64))

(def abs (-> F64 F64) (lambda (value.6) (if (< value.6 0.0) (- 0.0 value.6) value.6)))

(def workload-read (-> InputPort ReadResult)
  (lambda (port.1)
    ((lambda (result.1) (match result.1 ((read-error message) (datum-fail (string-append "read: " message))) ((read-value value.5) result.1) ((read-end) result.1)))
      (read port.1))))

(def real-datum (-> Datum F64)
  (lambda (value.4)
    (if (datum-number? value.4)
      (number->f64 (datum-number-value value.4))
      (datum-fail "sum1: expected a real number"))))

(def exact-datum (-> Datum I64)
  (lambda (value.3)
    (match (datum-number-value value.3)
      ((exact-number value) value)
      ((rational-number value.1) (datum-fail "benchmark count must fit an exact I64"))
      ((inexact-number value.2) (datum-fail "benchmark count must be exact"))
      ((complex-number real imaginary) (datum-fail "benchmark count must be exact")))))

(def read-from-file-benchmark (-> String Datum)
  (lambda (input)
    (call-with-input-file
      input
      (lambda (in)
        (((lambda () (begin (def loop.1 (lambda (x y i.1) (if (read-end? x) y (loop.1 (workload-read in) (read-value! x) (+ i.1 (ann 1 I64)))))) loop.1)))
          (workload-read in)
          (datum-boolean #f)
          (ann 0 I64))))))

(def Specification (datatype ()
  (specification
    (count I64 specification-count)
    (path String specification-path)
    (expected Datum specification-expected))))

(def read-specification (-> InputPort Specification)
  (lambda (port)
    ((lambda (count.2) ((lambda (path.1) ((lambda (expected.1) ((lambda () (specification count.2 path.1 expected.1)))) (read-value! (workload-read port)))) (datum-string-value (read-value! (workload-read port)))))
      (exact-datum (read-value! (workload-read port))))))

(def configured (call-with-input-file "input.txt" read-specification))

(def input0 (specification-path configured))

(def expected (specification-expected configured))

(def configured-count (-> I64) (lambda () (specification-count configured)))

(def hide-path (-> I64 String String) (lambda (count.1 path) (if (barrier) path (unreachable))))

(def bench (-> I64 I64)
  (lambda (count)
    (((lambda () (begin (def loop (lambda (i result) (if (< i count) (loop (+ i (ann 1 I64)) (read-from-file-benchmark (hide-path count input0))) (if (datum=? result expected) (ann 1 I64) (ann 0 I64))))) loop)))
      (ann 0 I64)
      (datum-boolean #f))))

(unit)
