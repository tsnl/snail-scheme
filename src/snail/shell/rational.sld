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

    (define one (→ Integer) (integer-from-i64 1))

    ;; Panics on a zero denominator.

    (define (make-rational (numerator Integer) (denominator Integer)) (→ Rational)
      (when (integer-zero? denominator) (panic "rational with zero denominator"))
      (let* ((divisor (integer-gcd numerator denominator))
             (divisor (if (integer-negative? denominator) (integer-negate divisor) divisor)))
        (Rational (integer-quotient numerator divisor) (integer-quotient denominator divisor))))

    (define (rational-from-integer (n Integer)) (→ Rational)
      (Rational n one))

    (define (rational-integer? (r Rational)) (→ Bool)
      (= (::denominator r) one))

    (define (rational->f64 (r Rational)) (→ F64)
      (/ (integer->f64 (::numerator r)) (integer->f64 (::denominator r))))

    (define (rational->string (r Rational)) (→ String)
      (if (rational-integer? r)
          (integer->string (::numerator r))
          (string-append (integer->string (::numerator r))
                         "/"
                         (integer->string (::denominator r)))))

    (define (rational-add (a Rational) (b Rational)) (→ Rational)
      (make-rational (+ (* (::numerator a) (::denominator b))
                        (* (::numerator b) (::denominator a)))
                     (* (::denominator a) (::denominator b))))

    (define (rational-subtract (a Rational) (b Rational)) (→ Rational)
      (rational-add a (Rational (integer-negate (::numerator b)) (::denominator b))))

    (define (rational-multiply (a Rational) (b Rational)) (→ Rational)
      (make-rational (* (::numerator a) (::numerator b))
                     (* (::denominator a) (::denominator b))))

    (define (rational-divide (a Rational) (b Rational)) (→ Rational)
      (make-rational (* (::numerator a) (::denominator b))
                     (* (::denominator a) (::numerator b))))

    ;; Denominators are positive, so cross-multiplying preserves order.

    (define (rational-compare (a Rational) (b Rational)) (→ I64)
      (integer-compare (* (::numerator a) (::denominator b))
                       (* (::numerator b) (::denominator a))))

    ))
