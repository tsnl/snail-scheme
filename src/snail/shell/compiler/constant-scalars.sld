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
          real-integer
          unicode-scalar)
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
    (define (real-integer (value F64)) (→ I64) (f64->i64 value))

    (extern unicode-upcase "snail.core.support" "snail:text/upcase" (Fn I32 → I32))
    (extern unicode-downcase "snail.core.support" "snail:text/downcase" (Fn I32 → I32))
    (extern unicode-foldcase "snail.core.support" "snail:text/foldcase" (Fn I32 → I32))
    (extern unicode-lowercase "snail.core.support" "snail:text/lowercase" (Fn I32 → I32))
    (extern unicode-uppercase "snail.core.support" "snail:text/uppercase" (Fn I32 → I32))
    (extern unicode-digit-value "snail.core.support" "snail:text/digit-value" (Fn I32 → I32))
    (extern unicode-alphabetic "snail.core.support" "snail:text/alphabetic" (Fn I32 → I32))
    (extern unicode-numeric "snail.core.support" "snail:text/numeric" (Fn I32 → I32))
    (extern unicode-whitespace "snail.core.support" "snail:datum/whitespace" (Fn I32 → I32))
    (extern unicode-full-fold-length
            "snail.core.support"
            "snail:text/full-fold-length"
            (Fn I32 → I32))
    (extern unicode-full-fold-scalar
            "snail.core.support"
            "snail:text/full-fold-scalar"
            (Fn I32 I32 → I32))

    (define (unicode-scalar (operation String) (code I32) (index I32)) (→ (Option I32))
      (case operation
        (("snail:text/upcase") (Some (unicode-upcase code)))
        (("snail:text/downcase") (Some (unicode-downcase code)))
        (("snail:text/foldcase") (Some (unicode-foldcase code)))
        (("snail:text/lowercase") (Some (unicode-lowercase code)))
        (("snail:text/uppercase") (Some (unicode-uppercase code)))
        (("snail:text/digit-value") (Some (unicode-digit-value code)))
        (("snail:text/alphabetic") (Some (unicode-alphabetic code)))
        (("snail:text/numeric") (Some (unicode-numeric code)))
        (("snail:datum/whitespace") (Some (unicode-whitespace code)))
        (("snail:text/full-fold-length") (Some (unicode-full-fold-length code)))
        (("snail:text/full-fold-scalar") (Some (unicode-full-fold-scalar code index)))
        (else (None))))))
