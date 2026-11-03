;; A finite dynamic arithmetic policy, built from the explicitly chosen
;; exact and inexact source instances. Importing it does not activate it.
(define-library (snail shell arithmetic dynamic)
  (export
   dynamic-arithmetic)
  (import
   (snail core base)
   (snail shell integer)
   (snail shell rational)
   (snail shell arithmetic))
  (begin
    (with-instances (arithmetic-base inexact-promotion)
                    (define-instance-set dynamic-arithmetic
                      (dynamic-instances Add
                                         (Integer Integer)
                                         (Integer Rational)
                                         (Integer F64)
                                         (Rational Integer)
                                         (Rational Rational)
                                         (Rational F64)
                                         (F64 Integer)
                                         (F64 Rational)
                                         (F64 F64))
                      (dynamic-instances Sub
                                         (Integer Integer)
                                         (Integer Rational)
                                         (Integer F64)
                                         (Rational Integer)
                                         (Rational Rational)
                                         (Rational F64)
                                         (F64 Integer)
                                         (F64 Rational)
                                         (F64 F64))
                      (dynamic-instances Mul
                                         (Integer Integer)
                                         (Integer Rational)
                                         (Integer F64)
                                         (Rational Integer)
                                         (Rational Rational)
                                         (Rational F64)
                                         (F64 Integer)
                                         (F64 Rational)
                                         (F64 F64))
                      (dynamic-instances Div
                                         (Integer Integer)
                                         (Integer Rational)
                                         (Integer F64)
                                         (Rational Integer)
                                         (Rational Rational)
                                         (Rational F64)
                                         (F64 Integer)
                                         (F64 Rational)
                                         (F64 F64))))))
