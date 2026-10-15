;; A rational owns two immutable Integers. Its constructor establishes the
;; positive, coprime denominator that every operation below may rely on.
(define-library (snail rational)
  (export Rational make-rational rational-numerator rational-denominator
          rational-from-integer rational-from-f64 rational->f64 rational->string
          rational-integer? rational-zero? rational-negative? rational-negate rational-abs
          rational-add rational-subtract rational-multiply rational-divide
          rational-compare rational=? rational<? rational<=? rational>? rational>=?
          rational-truncate rational-floor
          + - * / = < <= > >= truncate)
  (import (snail strict) (snail integer))
  (begin

    ;; ---- Normalization establishes the representation contract ----

    (define-data Rational
      (rational (numerator Integer rational-numerator) (denominator Integer rational-denominator)))
    (define one (integer-from-i64 1))
    (: make-rational (-> Integer Integer Rational))
    (define (make-rational numerator denominator)
      (if (integer-zero? denominator) (unreachable)
          (let* ((negative (integer-negative? denominator))
                 (numerator (if negative (integer-negate numerator) numerator))
                 (denominator (integer-abs denominator))
                 (factor (integer-gcd numerator denominator)))
            (rational (integer-quotient numerator factor) (integer-quotient denominator factor)))))
    (: rational-from-integer (-> Integer Rational))
    (define (rational-from-integer value) (rational value one))
    (: rational-integer? (-> Rational Bool))
    (define (rational-integer? value) (integer=? (rational-denominator value) one))
    (: rational-zero? (-> Rational Bool))
    (define (rational-zero? value) (integer-zero? (rational-numerator value)))
    (: rational-negative? (-> Rational Bool))
    (define (rational-negative? value) (integer-negative? (rational-numerator value)))
    (: rational-negate (-> Rational Rational))
    (define (rational-negate value)
      (rational (integer-negate (rational-numerator value)) (rational-denominator value)))
    (: rational-abs (-> Rational Rational))
    (define (rational-abs value) (if (rational-negative? value) (rational-negate value) value))

    ;; ---- Arithmetic remains exact before reducing the result ----

    (: rational-add (-> Rational Rational Rational))
    (define (rational-add left right)
      (make-rational
       (integer-add (integer-multiply (rational-numerator left) (rational-denominator right))
                    (integer-multiply (rational-numerator right) (rational-denominator left)))
       (integer-multiply (rational-denominator left) (rational-denominator right))))
    (: rational-subtract (-> Rational Rational Rational))
    (define (rational-subtract left right) (rational-add left (rational-negate right)))
    (: rational-multiply (-> Rational Rational Rational))
    (define (rational-multiply left right)
      (make-rational (integer-multiply (rational-numerator left) (rational-numerator right))
                     (integer-multiply (rational-denominator left) (rational-denominator right))))
    (: rational-divide (-> Rational Rational Rational))
    (define (rational-divide left right)
      (make-rational (integer-multiply (rational-numerator left) (rational-denominator right))
                     (integer-multiply (rational-denominator left) (rational-numerator right))))
    (: rational-truncate (-> Rational Integer))
    (define (rational-truncate value)
      (integer-quotient (rational-numerator value) (rational-denominator value)))
    (: rational-floor (-> Rational Integer))
    (define (rational-floor value)
      (integer-floor-quotient (rational-numerator value) (rational-denominator value)))

    ;; ---- Ordering uses positive denominators and exact cross products ----

    (: rational-compare (-> Rational Rational I64))
    (define (rational-compare left right)
      (integer-compare (integer-multiply (rational-numerator left) (rational-denominator right))
                       (integer-multiply (rational-numerator right) (rational-denominator left))))
    (: rational=? (-> Rational Rational Bool))
    (define (rational=? left right)
      (and (integer=? (rational-numerator left) (rational-numerator right))
           (integer=? (rational-denominator left) (rational-denominator right))))
    (: rational<? (-> Rational Rational Bool))
    (define (rational<? left right) (< (rational-compare left right) 0))
    (: rational<=? (-> Rational Rational Bool))
    (define (rational<=? left right) (<= (rational-compare left right) 0))
    (: rational>? (-> Rational Rational Bool))
    (define (rational>? left right) (> (rational-compare left right) 0))
    (: rational>=? (-> Rational Rational Bool))
    (define (rational>=? left right) (>= (rational-compare left right) 0))

    ;; ---- Binary64 exactness and decimal presentation ----

    ;; A finite fractional binary64 is smaller than 2^52. Scaling it by 2^30
    ;; is exact and cannot overflow. At most 36 steps make every finite binary64
    ;; integral, including the smallest subnormal. Normalization removes powers
    ;; of two shared by the scaled integer and denominator; -0.0 becomes 0/1.
    (: rational-from-f64 (-> F64 Rational))
    (define (rational-from-f64 value)
      (if (not (and (= value value) (< value (/ 1.0 0.0)) (> value (/ -1.0 0.0)))) (unreachable)
          (let loop ((value value) (exponent 0))
            (if (= value (truncate value))
                (make-rational (integer-from-f64 value) (integer-power (integer-from-i64 2) exponent))
                (loop (* value 1073741824.0) (+ exponent 30))))))
    (: rational->f64 (-> Rational F64))
    (define (rational->f64 value)
      (integer-ratio->f64 (rational-numerator value) (rational-denominator value)))
    (: rational->string (-> Rational String))
    (define (rational->string value)
      (let ((numerator (integer->string (rational-numerator value))))
        (if (rational-integer? value) numerator
            (string-append numerator "/" (integer->string (rational-denominator value))))))

    ;; ---- Existing static operator families retain concrete operands ----

    (define-overload + (-> Rational Rational Rational) rational-add)
    (define-overload - (-> Rational Rational Rational) rational-subtract)
    (define-overload - (-> Rational Rational) rational-negate)
    (define-overload * (-> Rational Rational Rational) rational-multiply)
    (define-overload / (-> Rational Rational Rational) rational-divide)
    (define-overload / (-> Integer Integer Rational) make-rational)
    (define-overload = (-> Rational Rational Bool) rational=?)
    (define-overload < (-> Rational Rational Bool) rational<?)
    (define-overload <= (-> Rational Rational Bool) rational<=?)
    (define-overload > (-> Rational Rational Bool) rational>?)
    (define-overload >= (-> Rational Rational Bool) rational>=?)
    (define-overload truncate (-> Rational Integer) rational-truncate))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-rational)
    (begin
      (define (test-rational)
        (let* ((half (make-rational (integer-from-i64 2) (integer-from-i64 -4)))
               (zero (make-rational (integer-from-i64 0) (integer-from-i64 -9))))
          (unless (and (string=? (rational->string half) "-1/2")
                       (string=? (rational->string zero) "0")
                       (integer=? (rational-denominator zero) (integer-from-i64 1))
                       (rational=? (rational-from-f64 -0.5) half)
                       (rational=? (rational-add half (rational-negate half)) zero))
            (unreachable))
          42))))))
