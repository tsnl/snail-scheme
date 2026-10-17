(import (lofi base) (lofi integer) (lofi number)
        (only (lofi primitive) i64-wrapping-add i64-wrapping-mul
              f64-ieee-add f64-ieee-sub f64-ieee-mul f64-ieee-div))

(def require (-> Bool Unit) (lambda (condition) (if condition (unit) (unreachable))))
(def maximum 1.7976931348623157e308)
(def wrapping-add (ref i64-wrapping-add))
(def wrapping-mul (ref i64-wrapping-mul))
(def ieee-operations (vector f64-ieee-add f64-ieee-sub f64-ieee-mul f64-ieee-div))
(def power-two (-> I64 Integer)
     (lambda (exponent) (integer-power (integer-from-i64 (ann 2 I64)) exponent)))

;; Ordinary word arithmetic wraps, including negation expressed as subtraction.
(require (= (+ (ann 9223372036854775807 I64) (ann 1 I64)) (ann -9223372036854775808 I64)))
(require (= (- (ann 0 I64) (ann -9223372036854775808 I64)) (ann -9223372036854775808 I64)))
(require (= (- 0 -2147483648) -2147483648))

;; Named word aliases retain the same contract, including function values.
(require (= (i64-wrapping-add (ann 9223372036854775807 I64) (ann 1 I64)) (ann -9223372036854775808 I64)))
(require (= ((ref-get wrapping-add) (ann 9223372036854775807 I64) (ann 1 I64)) (ann -9223372036854775808 I64)))
(require (= (i64-wrapping-mul (ann 4294967296 I64) (ann 4294967296 I64)) (ann 0 I64)))
(require (= ((ref-get wrapping-mul) (ann -9223372036854775808 I64) (ann -1 I64)) (ann -9223372036854775808 I64)))

;; Ordinary floats and compatibility aliases retain IEEE overflow results.
(require (= (+ maximum maximum) +inf.0))
(require (= (- maximum (- 0.0 maximum)) +inf.0))
(require (= (* maximum 2.0) +inf.0))
(require (= (/ maximum 0.5) +inf.0))
(require (= (f64-ieee-add maximum maximum) +inf.0))
(require (= (f64-ieee-sub maximum (- 0.0 maximum)) +inf.0))
(require (= (f64-ieee-mul maximum 2.0) +inf.0))
(require (= (f64-ieee-div maximum 0.5) +inf.0))
(require (= ((vector-ref ieee-operations (ann 0 I64)) maximum maximum) +inf.0))
(require (= ((vector-ref ieee-operations (ann 1 I64)) maximum (- 0.0 maximum)) +inf.0))
(require (= ((vector-ref ieee-operations (ann 2 I64)) maximum 2.0) +inf.0))
(require (= ((vector-ref ieee-operations (ann 3 I64)) maximum 0.5) +inf.0))

;; The nominal numeric tower deliberately keeps its inexact IEEE contract.
(require (= (number->f64 (number-add (inexact-number maximum) (inexact-number maximum))) +inf.0))
(require (= (number->f64 (number-subtract (inexact-number maximum) (inexact-number (- 0.0 maximum)))) +inf.0))
(require (= (number->f64 (number-multiply (inexact-number maximum) (inexact-number 2.0))) +inf.0))
(require (= (number->f64 (number-divide (inexact-number maximum) (inexact-number 0.5))) +inf.0))

;; Exact-to-F64 conversion rounds at the boundary, including infinity and -0.
(def two-to-1024 (power-two (ann 1024 I64)))
(def midpoint (integer-subtract two-to-1024 (power-two (ann 970 I64))))
(require (= (integer->f64 two-to-1024) +inf.0))
(require (= (integer->f64 midpoint) +inf.0))
(require (= (integer->f64 (integer-subtract midpoint (integer-from-i64 (ann 1 I64)))) maximum))
(require (= (integer->f64 (integer-subtract two-to-1024 (power-two (ann 971 I64)))) maximum))
(require (= (/ 1.0 (integer-ratio->f64 (integer-from-i64 (ann -1 I64)) (power-two (ann 1076 I64)))) -inf.0))
42
