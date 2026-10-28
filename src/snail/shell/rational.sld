;; Exact rationals. The constructor establishes a positive denominator
;; coprime with the numerator, which equality and comparison rely on.
(define-library (snail shell rational)
  (export
   Rational
   Rational-numerator
   Rational-denominator
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
    (: make-rational (-> Integer Integer Rational))
    (define (make-rational numerator denominator)
      (when (integer-zero? denominator) (panic "rational with zero denominator"))
      (let* ((divisor (integer-gcd numerator denominator))
             (divisor (if (integer-negative? denominator) (integer-negate divisor) divisor)))
        (Rational (integer-quotient numerator divisor) (integer-quotient denominator divisor))))

    (: rational-from-integer (-> Integer Rational))
    (define (rational-from-integer n)
      (Rational n one))

    (: rational-integer? (-> Rational Bool))
    (define (rational-integer? r)
      (= (Rational-denominator r) one))

    (: rational->f64 (-> Rational F64))
    (define (rational->f64 r)
      (/ (integer->f64 (Rational-numerator r)) (integer->f64 (Rational-denominator r))))

    (: rational->string (-> Rational String))
    (define (rational->string r)
      (if (rational-integer? r)
          (integer->string (Rational-numerator r))
          (string-append (integer->string (Rational-numerator r))
                         "/"
                         (integer->string (Rational-denominator r)))))

    (: rational-add (-> Rational Rational Rational))
    (define (rational-add a b)
      (make-rational (+ (* (Rational-numerator a) (Rational-denominator b))
                        (* (Rational-numerator b) (Rational-denominator a)))
                     (* (Rational-denominator a) (Rational-denominator b))))

    (: rational-subtract (-> Rational Rational Rational))
    (define (rational-subtract a b)
      (rational-add a (Rational (integer-negate (Rational-numerator b)) (Rational-denominator b))))

    (: rational-multiply (-> Rational Rational Rational))
    (define (rational-multiply a b)
      (make-rational (* (Rational-numerator a) (Rational-numerator b))
                     (* (Rational-denominator a) (Rational-denominator b))))

    (: rational-divide (-> Rational Rational Rational))
    (define (rational-divide a b)
      (make-rational (* (Rational-numerator a) (Rational-denominator b))
                     (* (Rational-denominator a) (Rational-numerator b))))

    ;; Denominators are positive, so cross-multiplying preserves order.
    (: rational-compare (-> Rational Rational I64))
    (define (rational-compare a b)
      (integer-compare (* (Rational-numerator a) (Rational-denominator b))
                       (* (Rational-numerator b) (Rational-denominator a))))

    ))
