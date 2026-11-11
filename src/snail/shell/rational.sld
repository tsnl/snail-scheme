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
      (= (● r denominator) one))

    (define (rational->f64 (r Rational)) (→ F64)
      (/ (integer->f64 (● r numerator)) (integer->f64 (● r denominator))))

    (define (rational->string (r Rational)) (→ String)
      (if (rational-integer? r)
          (integer->string (● r numerator))
          (string-append (integer->string (● r numerator))
                         "/"
                         (integer->string (● r denominator)))))

    (define (rational-add (a Rational) (b Rational)) (→ Rational)
      (make-rational (+ (* (● a numerator) (● b denominator))
                        (* (● b numerator) (● a denominator)))
                     (* (● a denominator) (● b denominator))))

    (define (rational-subtract (a Rational) (b Rational)) (→ Rational)
      (rational-add a (Rational (integer-negate (● b numerator)) (● b denominator))))

    (define (rational-multiply (a Rational) (b Rational)) (→ Rational)
      (make-rational (* (● a numerator) (● b numerator))
                     (* (● a denominator) (● b denominator))))

    (define (rational-divide (a Rational) (b Rational)) (→ Rational)
      (make-rational (* (● a numerator) (● b denominator))
                     (* (● a denominator) (● b numerator))))

    ;; Denominators are positive, so cross-multiplying preserves order.

    (define (rational-compare (a Rational) (b Rational)) (→ I64)
      (integer-compare (* (● a numerator) (● b denominator))
                       (* (● b numerator) (● a denominator))))

    ))
