;; The constant interpreter needs correctly rounded decimal input and exact
;; IEEE representations. These are the same scalar services used by emitted
;; code; the Chez bootstrap supplies this small boundary natively.
(define-library (snail shell compiler constant-scalars)
  (export read-real
          round-single
          real-bits
          bits-real
          single-bits
          bits-single
          integer-real
          real-integer)
  (import
   (snail core base))
  (begin
    (extern parse-real "snail.core.support" "snail:datum/parse-real" (Fn String → I32))
    (extern parsed-real "snail.core.support" "snail:datum/parsed-real" (Fn → F64))

    (define (read-real (text String)) (→ (Option F64))
      (if (= (parse-real text) (i64->i32 1)) (Some (parsed-real)) (None)))

    (define (round-single (value F64)) (→ F64) (f32->f64 (f64->f32 value)))
    (define (real-bits (value F64)) (→ I64) (f64->bits value))
    (define (bits-real (value I64)) (→ F64) (bits->f64 value))
    (define (single-bits (value F64)) (→ I32) (f32->bits (f64->f32 value)))
    (define (bits-single (value I32)) (→ F64) (f32->f64 (bits->f32 value)))
    (define (integer-real (value I64)) (→ F64) (i64->f64 value))
    (define (real-integer (value F64)) (→ I64) (f64->i64 value))))
