;; Scheme numbers: exact rationals of any size, and inexact reals. An
;; operation is exact when all its operands are. Complex numbers, radix
;; prefixes and exactness prefixes are not supported.
(define-library (snail shell number)
  (export
   Number
   Exact
   Inexact
   number-from-i64
   number-from-f64
   number-from-integer
   number-exact?
   number-integer?
   number->f64
   number->string
   string->number
   number-add
   number-subtract
   number-multiply
   number-divide
   number-compare
   number-exact
   number-inexact)
  (import
   (snail core base)
   (snail shell integer)
   (snail shell rational))
  (begin

    ;; ---- Representation ----

    (enum Number
      (Exact ((value Rational)))
      (Inexact ((value F64))))

    (define (number-from-i64 (value I64)) (→ Number)
      (Exact (rational-from-integer (integer-from-i64 value))))

    (define (number-from-integer (value Integer)) (→ Number)
      (Exact (rational-from-integer value)))

    (define (number-from-f64 (value F64)) (→ Number)
      (Inexact value))

    (define (number-exact? (n Number)) (→ Bool)
      (match n
        ((Exact _) #t)
        ((Inexact _) #f)))

    (define (number-integer? (n Number)) (→ Bool)
      (match n
        ((Exact r) (rational-integer? r))
        ((Inexact x) (= x (floor x)))))

    (define (number->f64 (n Number)) (→ F64)
      (match n
        ((Exact r) (rational->f64 r))
        ((Inexact x) x)))

    (define (number-inexact (n Number)) (→ Number)
      (Inexact (number->f64 n)))

    ;; Exact only for integral reals; the conversion truncates otherwise.

    (define (number-exact (n Number)) (→ Number)
      (match n
        ((Exact _) n)
        ((Inexact x) (number-from-i64 (f64->i64 x)))))

    ;; ---- Arithmetic ----

    ;; Applies the exact operation when both operands are exact, and the
    ;; inexact one otherwise.

    (define (combine (exact (dyn (Fn Rational Rational → Rational)))
                     (inexact (dyn (Fn F64 F64 → F64)))
                     (a Number)
                     (b Number))
      (→ Number)
      (match a
        ((Exact x) (match b
                     ((Exact y) (Exact (exact x y)))
                     ((Inexact y) (Inexact (inexact (rational->f64 x) y)))))
        ((Inexact x) (Inexact (inexact x (number->f64 b))))))

    (define (number-add (a Number) (b Number)) (→ Number)
      (combine rational-add + a b))

    (define (number-subtract (a Number) (b Number)) (→ Number)
      (combine rational-subtract - a b))

    (define (number-multiply (a Number) (b Number)) (→ Number)
      (combine rational-multiply * a b))

    (define (number-divide (a Number) (b Number)) (→ Number)
      (combine rational-divide / a b))

    (define (number-compare (a Number) (b Number)) (→ I64)
      (match a
        ((Exact x) (match b
                     ((Exact y) (rational-compare x y))
                     ((Inexact y) (compare-reals (rational->f64 x) y))))
        ((Inexact x) (compare-reals x (number->f64 b)))))

    (define (compare-reals (x F64) (y F64)) (→ I64)
      (cond ((< x y) -1)
            ((> x y) 1)
            (else 0)))

    (instance (Num (!) Number)
      (define + number-add)
      (define - number-subtract)
      (define * number-multiply)
      (define negate (lambda (n) (number-subtract (number-from-i64 0) n))))

    (instance (Ord (!) Number)
      (define = (lambda (a b) (= (number-compare a b) 0)))
      (define < (lambda (a b) (< (number-compare a b) 0)))
      (define <= (lambda (a b) (<= (number-compare a b) 0)))
      (define > (lambda (a b) (> (number-compare a b) 0)))
      (define >= (lambda (a b) (>= (number-compare a b) 0))))

    ;; ---- Text ----

    (define (number->string (n Number)) (→ String)
      (match n
        ((Exact r) (rational->string r))
        ((Inexact x) (f64->string x))))

    (instance (Show (!) Number)
      (define show number->string))

    ;; Exact integers and ratios are parsed here; the runtime parses reals,
    ;; such as decimals, exponents and infinities, with correct rounding.

    (define (string->number (text String)) (→ (Option Number))
      (match (string-index text #\/)
        ((Some slash)
         (match (string->integer (substring text 0 slash))
           ((Some numerator)
            (match (string->integer (substring text (+ slash 1) (string-length text)))
              ((Some denominator)
               (if (integer-zero? denominator)
                   (None)
                   (Some (Exact (make-rational numerator denominator)))))
              ((None) (None))))
           ((None) (None))))
        ((None)
         (match (string->integer text)
           ((Some n) (Some (number-from-integer n)))
           ((None) (runtime-real text))))))

    (extern parse-real "snail.core.support" "snail:datum/parse-real" (impl (Fn String → I32)))
    (extern parsed-real "snail.core.support" "snail:datum/parsed-real" (impl (Fn → F64)))

    ;; Read the scratch result only on success, before returning to user code.

    (define (runtime-real (text String)) (→ (Option Number))
      (if (= (parse-real text) 1) (Some (Inexact (parsed-real))) (None)))

    ))
