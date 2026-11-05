#lang snail
define-library (sample reader-layout)
  export twice
  import (snail core base) (sample reader-sexp)
  begin
    : twice (-> I64 I64)
    define (twice n)
      + n (identity n)
