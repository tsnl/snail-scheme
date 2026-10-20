;; Scheme numbers: exact rationals of any size, and inexact reals. An
;; operation is exact when all its operands are. Complex numbers are not
;; supported.
(define-library (lofi number)
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
   (lofi base)
   (lofi integer)
   (lofi rational))
  (begin

    ;; ---- Representation ----

    (enum Number
      (Exact ((value Rational)))
      (Inexact ((value F64))))

    (: number-from-i64 (-> I64 Number))
    (define (number-from-i64 value)
      (Exact (rational-from-integer (integer-from-i64 value))))

    (: number-from-integer (-> Integer Number))
    (define (number-from-integer value)
      (Exact (rational-from-integer value)))

    (: number-from-f64 (-> F64 Number))
    (define (number-from-f64 value)
      (Inexact value))

    (: number-exact? (-> Number Bool))
    (define (number-exact? n)
      (match n
        ((Exact _) #t)
        ((Inexact _) #f)))

    (: number-integer? (-> Number Bool))
    (define (number-integer? n)
      (match n
        ((Exact r) (rational-integer? r))
        ((Inexact x) (= x (floor x)))))

    (: number->f64 (-> Number F64))
    (define (number->f64 n)
      (match n
        ((Exact r) (rational->f64 r))
        ((Inexact x) x)))

    (: number-inexact (-> Number Number))
    (define (number-inexact n)
      (Inexact (number->f64 n)))

    ;; Exact only for integral reals; the conversion truncates otherwise.
    (: number-exact (-> Number Number))
    (define (number-exact n)
      (match n
        ((Exact _) n)
        ((Inexact x) (number-from-i64 (f64->i64 x)))))

    ;; ---- Arithmetic ----

    ;; Applies the exact operation when both operands are exact, and the
    ;; inexact one otherwise.
    (: combine (-> (-> Rational Rational Rational) (-> F64 F64 F64) Number Number Number))
    (define (combine exact inexact a b)
      (match a
        ((Exact x) (match b
                     ((Exact y) (Exact (exact x y)))
                     ((Inexact y) (Inexact (inexact (rational->f64 x) y)))))
        ((Inexact x) (Inexact (inexact x (number->f64 b))))))

    (: number-add (-> Number Number Number))
    (define (number-add a b)
      (combine rational-add + a b))

    (: number-subtract (-> Number Number Number))
    (define (number-subtract a b)
      (combine rational-subtract - a b))

    (: number-multiply (-> Number Number Number))
    (define (number-multiply a b)
      (combine rational-multiply * a b))

    (: number-divide (-> Number Number Number))
    (define (number-divide a b)
      (combine rational-divide / a b))

    (: number-compare (-> Number Number I64))
    (define (number-compare a b)
      (match a
        ((Exact x) (match b
                     ((Exact y) (rational-compare x y))
                     ((Inexact y) (compare-reals (rational->f64 x) y))))
        ((Inexact x) (compare-reals x (number->f64 b)))))

    (: compare-reals (-> F64 F64 I64))
    (define (compare-reals x y)
      (cond ((< x y) -1)
            ((> x y) 1)
            (else 0)))

    (instance (Num Number)
      (define + number-add)
      (define - number-subtract)
      (define * number-multiply)
      (define (negate n) (number-subtract (number-from-i64 0) n)))

    (instance (Ord Number)
      (define (= a b) (= (number-compare a b) 0))
      (define (< a b) (< (number-compare a b) 0))
      (define (<= a b) (<= (number-compare a b) 0))
      (define (> a b) (> (number-compare a b) 0))
      (define (>= a b) (>= (number-compare a b) 0)))

    ;; ---- Text ----

    (: number->string (-> Number String))
    (define (number->string n)
      (match n
        ((Exact r) (rational->string r))
        ((Inexact x) (f64->string x))))

    (instance (Show Number)
      (define show number->string))

    ;; Exact integers and ratios are parsed here; the runtime parses every
    ;; other numeric syntax, such as decimals, exponents and radix prefixes.
    (: string->number (-> String (Option Number)))
    (define (string->number text)
      (match (string-index text #\/)
        ((Some slash)
         (match (string->integer (substring text 0 slash))
           ((Some numerator)
            (match (string->integer (substring text (+ slash 1) (string-length text)))
              ((Some denominator) (if (integer-zero? denominator) (None) (Some (Exact (make-rational numerator denominator)))))
              ((None) (None))))
           ((None) (None))))
        ((None)
         (match (string->integer text)
           ((Some n) (Some (number-from-integer n)))
           ((None) (runtime-number text))))))

    (extern token-open "snail.library" "snail:datum/token-open" (-> I32))
    (extern token-character "snail.library" "snail:datum/token-character" (-> I32 Char Unit))
    (extern token-parse "snail.library" "snail:datum/token-parse" (-> I32 I32))
    (extern token-close "snail.library" "snail:datum/token-close" (-> I32 Unit))
    (extern number-real "snail.library" "snail:datum/number-real" (-> I32 I32 F64))
    (extern number-integer "snail.library" "snail:datum/number-integer" (-> I32 I32 I64))

    ;; The token handle is owned only within this call.
    (: runtime-number (-> String (Option Number)))
    (define (runtime-number text)
      (let ((token (token-open)))
        (let loop ((index 0))
          (when (< index (string-length text))
            (token-character token (string-ref text index))
            (loop (+ index 1))))
        (let* ((kind (token-parse token))
               (result (case kind
                         ((1) (Some (number-from-i64 (number-integer token 0))))
                         ((2) (Some (Inexact (number-real token 0))))
                         (else (None)))))
          (token-close token)
          result)))

    ))
