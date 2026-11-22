;; Reals print as the shortest decimal that reads back as them, laid out
;; positionally from 1e-4 up to 1e16 and in scientific notation otherwise:
;; zeros, the layout's edges, subnormals, powers of two (whose interval is
;; lopsided), ties and the extremes. (snail core base) computes the digits.
(import
 (snail core base)
 (snail core io))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (for-each (lambda (value) (write-line out (show value)))
            (list 0.0
                  (negate 0.0)
                  1.0
                  -1.5
                  0.1
                  (+ 0.1 0.2)
                  (/ 1.0 3.0)
                  100.0
                  123456.789
                  1e15
                  9999999999999998.0
                  1e16
                  1e22
                  1e21
                  0.0001
                  9.999999999999999e-5
                  2.5e-8
                  1.25e-18
                  9.223372036854776e18
                  9007199254740992.0
                  1.152921504606847e18
                  5e-324
                  1e-323
                  2.225073858507201e-308
                  2.2250738585072014e-308
                  1.7976931348623157e308
                  (/ 0.0 0.0)
                  (/ 1.0 0.0)
                  (/ -1.0 0.0)))
  (write-line out (show (f64->f32 0.1))))
