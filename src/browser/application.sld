;; Scalar browser application support, shared by Scheme and Lofi callers.
(define-library (browser application)
  (export Quad quad quad-x quad-y quad-width quad-height quad-rgb quad-opacity
          text-scalar integer-text)
  (import
   (scheme base)
   (only (lofi base) string-append i32->i64 i64->i32)
   (only (lofi core) datatype ann I32 I64))
  (begin

    ;; ---- Immutable presentation data ----

    ;; Logical pixels, packed RGB and opacity 0..255; no live GPU handles.
    (define Quad
      (datatype ()
        (quad
         (x I32 quad-x)
         (y I32 quad-y)
         (width I32 quad-width)
         (height I32 quad-height)
         (rgb I32 quad-rgb)
         (opacity I32 quad-opacity))))

    ;; ---- Copied text and decimal presentation ----

    (define (text-scalar text index)
      (if (< index 0) (i64->i32 (string-length text))
          (if (< (i32->i64 index) (string-length text))
              (i64->i32 (char->integer (string-ref text (i32->i64 index)))) 0)))
    (define (positive-text value)
      (let ((digit (string (integer->char (+ (ann 48 I64) (remainder value (ann 10 I64)))))))
        (if (< value (ann 10 I64)) digit
            (string-append (positive-text (quotient value (ann 10 I64))) digit))))
    (define (integer-text value)
      (let ((wide (i32->i64 value)))
        (if (< wide (ann 0 I64)) (string-append "-" (positive-text (- (ann 0 I64) wide)))
            (positive-text wide))))))
