;; Exact rationals. The constructor establishes a positive denominator
;; coprime with the numerator, which equality and comparison rely on.
(define-library (snail shell rational)
  (export
   Rational
   make-rational
   rational-from-integer
   rational-integer?
   rational->f64
   rational->string
   rational-add
   rational-subtract
   rational-multiply
   rational-divide
   rational-compare)
  (import
   (snail core base)
   (snail shell integer))
  (begin

    (struct Rational
      ((numerator Integer)
       (denominator Integer)))

    (: one Integer)
    (define one (integer-from-i64 1))

    ;; Panics on a zero denominator.
    (: make-rational (impl (Fn Integer Integer -> Rational)))
    (define (make-rational numerator denominator)
      (when (integer-zero? denominator) (panic "rational with zero denominator"))
      (let* ((divisor (integer-gcd numerator denominator))
             (divisor (if (integer-negative? denominator) (integer-negate divisor) divisor)))
        (Rational (integer-quotient numerator divisor) (integer-quotient denominator divisor))))

    (: rational-from-integer (impl (Fn Integer -> Rational)))
    (define (rational-from-integer n)
      (Rational n one))

    (: rational-integer? (impl (Fn Rational -> Bool)))
    (define (rational-integer? r)
      (= (::denominator r) one))

    (: rational->f64 (impl (Fn Rational -> F64)))
    (define (rational->f64 r)
      (/ (integer->f64 (::numerator r)) (integer->f64 (::denominator r))))

    (: rational->string (impl (Fn Rational -> String)))
    (define (rational->string r)
      (if (rational-integer? r)
          (integer->string (::numerator r))
          (string-append (integer->string (::numerator r))
                         "/"
                         (integer->string (::denominator r)))))

    (: rational-add (impl (Fn Rational Rational -> Rational)))
    (define (rational-add a b)
      (make-rational (+ (* (::numerator a) (::denominator b))
                        (* (::numerator b) (::denominator a)))
                     (* (::denominator a) (::denominator b))))

    (: rational-subtract (impl (Fn Rational Rational -> Rational)))
    (define (rational-subtract a b)
      (rational-add a (Rational (integer-negate (::numerator b)) (::denominator b))))

    (: rational-multiply (impl (Fn Rational Rational -> Rational)))
    (define (rational-multiply a b)
      (make-rational (* (::numerator a) (::numerator b))
                     (* (::denominator a) (::denominator b))))

    (: rational-divide (impl (Fn Rational Rational -> Rational)))
    (define (rational-divide a b)
      (make-rational (* (::numerator a) (::denominator b))
                     (* (::denominator a) (::numerator b))))

    ;; Denominators are positive, so cross-multiplying preserves order.
    (: rational-compare (impl (Fn Rational Rational -> I64)))
    (define (rational-compare a b)
      (integer-compare (* (::numerator a) (::denominator b))
                       (* (::numerator b) (::denominator a))))

    ))
