(import (scheme base) (scheme write) (snail-scheme iverson-ghost))

;; ---- Small concrete tensor programs ----

(define samples (array '(3 2) '(1 2 3 4 5 6) 'f32))
(define centered (sub samples (mean samples 0)))
(define covariance (div (matmul (transpose centered) centered) 3))

;; Repeated integer indices accumulate into a dense histogram.
(define labels (array '(5) '(2 0 2 1 2) 'i32))
(define counts (scatter-add (array '(3) '(0 0 0) 'i32) labels 1))

;; A standard vector already participates as an object tensor.
(define names '#(zero one two))

(define (show label value)
  (display label)
  (write (list (dtype value) (shape value) (array->vector value)))
  (newline))

(show "centered: " centered)
(show "covariance: " covariance)
(show "histogram: " counts)
(show "gathered names: " (gather names labels))
