(import
 (snail core base)
 (snail core io))

(define (overflow) (→ I64) (+ 9223372036854775807 1))

(define (multiply) (→ I64) (* 9223372036854775807 9223372036854775807))

(define (shift) (→ I64) (i64-shift-right/logical -1 1))

(define (real) (→ F64) (/ 1.0 10.0))

(define (single) (→ F32) (/ (ann 1.0 F32) (ann 10.0 F32)))

(define (zero) (→ F64) (ceiling -0.5))

(define (nan) (→ F64) (sqrt -1.0))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (display out (overflow))
  (newline out)
  (display out (multiply))
  (newline out)
  (display out (shift))
  (newline out)
  (display out (f64->bits (real)))
  (newline out)
  (display out (f32->bits (single)))
  (newline out)
  (display out (f64->bits (zero)))
  (newline out)
  (display out (= (nan) (nan)))
  (newline out)
  (unit))
