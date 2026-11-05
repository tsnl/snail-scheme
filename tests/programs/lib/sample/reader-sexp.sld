#lang snail/sexp
(define-library (sample reader-sexp)
  (export identity)
  (import (snail core base))
  (begin
    (: identity (-> I64 I64)) (define (identity n) n)))
