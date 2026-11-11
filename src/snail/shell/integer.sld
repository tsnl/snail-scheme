;; Exact integers of any size. A magnitude is a vector of base-10^9 limbs,
;; least significant first, with no high zero limbs; zero has no limbs and is
;; never negative. Every function returns canonical integers, which equality
;; and comparison rely on.
(define-library (snail shell integer)
  (export
   Integer
   integer-from-i64
   integer->i64
   integer-fits-i64?
   integer->f64
   integer->string
   string->integer
   integer-zero?
   integer-negative?
   integer-negate
   integer-abs
   integer-compare
   integer-add
   integer-subtract
   integer-multiply
   integer-quotient
   integer-remainder
   integer-modulo
   integer-gcd
   integer-expt)
  (import
   (snail core base))
  (begin

    ;; ---- Representation ----

    (struct Integer
      ((negative Bool)
       (limbs (Vector I64))))

    (define base (→ I64) 1000000000)

    (define no-limbs (→ (Vector I64)) (vector-generate 0 (lambda (index) 0)))

    ;; Drops high zero limbs and gives zero its one sign.

    (define (canonical (negative Bool) (limbs (Vector I64))) (→ Integer)
      (let loop ((length (vector-length limbs)))
        (cond ((= length 0) (Integer #f no-limbs))
              ((= (vector-ref limbs (- length 1)) 0) (loop (- length 1)))
              (else (Integer negative (subvector limbs 0 length))))))

    (define (limb (limbs (Vector I64)) (index I64)) (→ I64)
      (if (< index (vector-length limbs)) (vector-ref limbs index) 0))

    (define (integer-from-i64 (value I64)) (→ Integer)
      (if (= value -9223372036854775808)
          (integer-subtract (integer-from-i64 -9223372036854775807) (integer-from-i64 1))
          (let loop ((rest (abs value)) (limbs (Nil)))
            (if (= rest 0)
                (canonical (< value 0) (list->vector (reverse limbs)))
                (loop (quotient rest base) (Cons (remainder rest base) limbs))))))

    (define (integer-zero? (n Integer)) (→ Bool)
      (= (vector-length (● n limbs)) 0))

    (define (integer-negative? (n Integer)) (→ Bool)
      (● n negative))

    (define (integer-negate (n Integer)) (→ Integer)
      (canonical (not (● n negative)) (● n limbs)))

    (define (integer-abs (n Integer)) (→ Integer)
      (Integer #f (● n limbs)))

    ;; ---- Conversions ----

    (define (integer-fits-i64? (n Integer)) (→ Bool)
      (and (<= (integer-compare n (integer-from-i64 9223372036854775807)) 0)
           (>= (integer-compare n (integer-from-i64 -9223372036854775807)) 0)))

    ;; Wraps when the integer does not fit.

    (define (integer->i64 (n Integer)) (→ I64)
      (let ((magnitude (vector-fold (lambda (total limb) (+ (* total base) limb)) 0
                                    (reverse-vector (● n limbs)))))
        (if (● n negative) (negate magnitude) magnitude)))

    (define (integer->f64 (n Integer)) (→ F64)
      (let ((magnitude
             (vector-fold (lambda (total limb) (+ (* total 1000000000.0) (i64->f64 limb))) 0.0
                          (reverse-vector (● n limbs)))))
        (if (● n negative) (negate magnitude) magnitude)))

    (define (reverse-vector (items (Vector I64))) (→ (Vector I64))
      (vector-generate (vector-length items)
                       (lambda (index) (vector-ref items (- (- (vector-length items) 1) index)))))

    (define (integer->string (n Integer)) (→ String)
      (let ((limbs (● n limbs)))
        (if (integer-zero? n)
            "0"
            (string-concatenate
             (Cons (if (● n negative) "-" "")
                   (Cons (show (vector-ref limbs (- (vector-length limbs) 1)))
                         (map (lambda (index) (padded-limb (vector-ref limbs index)))
                              (reverse (iota (- (vector-length limbs) 1))))))))))

    (define (padded-limb (value I64)) (→ String)
      (let ((digits (show value)))
        (string-append (make-string (- 9 (string-length digits)) #\0) digits)))

    ;; Optional sign, then decimal digits. None if the text is not an integer.

    (define (string->integer (text String)) (→ (Option Integer))
      (let* ((negative (and (> (string-length text) 0) (= (string-ref text 0) #\-)))
             (start
              (if (and (> (string-length text) 0) (or negative (= (string-ref text 0) #\+))) 1 0))
             (digits (substring text start (string-length text))))
        (if (and (> (string-length digits) 0) (every? char-numeric? (string->list digits)))
            (Some (canonical negative (decimal-limbs digits)))
            (None))))

    (define (decimal-limbs (digits String)) (→ (Vector I64))
      (let ((count (quotient (+ (string-length digits) 8) 9)))
        (vector-generate count
                         (lambda (index)
                           (let* ((end (- (string-length digits) (* 9 index)))
                                  (start (max 0 (- end 9))))
                             (fold-left (lambda (value char) (+ (* value 10) (digit-value char))) 0
                                        (string->list (substring digits start end))))))))

    ;; ---- Comparison ----

    (define (compare-magnitudes (a (Vector I64)) (b (Vector I64))) (→ I64)
      (if (= (vector-length a) (vector-length b))
          (let loop ((index (- (vector-length a) 1)))
            (cond ((< index 0) 0)
                  ((< (vector-ref a index) (vector-ref b index)) -1)
                  ((> (vector-ref a index) (vector-ref b index)) 1)
                  (else (loop (- index 1)))))
          (if (< (vector-length a) (vector-length b)) -1 1)))

    ;; -1, 0 or 1.

    (define (integer-compare (a Integer) (b Integer)) (→ I64)
      (cond ((and (● a negative) (not (● b negative))) -1)
            ((and (● b negative) (not (● a negative))) 1)
            ((● a negative) (compare-magnitudes (● b limbs) (● a limbs)))
            (else (compare-magnitudes (● a limbs) (● b limbs)))))

    ;; ---- Addition ----

    (define (add-magnitudes (a (Vector I64)) (b (Vector I64))) (→ (Vector I64))
      (let ((count (+ 1 (max (vector-length a) (vector-length b)))))
        (carry-limbs (vector-generate count (lambda (index) (+ (limb a index) (limb b index)))))))

    ;; Requires |a| >= |b|.

    (define (subtract-magnitudes (a (Vector I64)) (b (Vector I64))) (→ (Vector I64))
      (carry-limbs
       (vector-generate (vector-length a) (lambda (index) (- (limb a index) (limb b index))))))

    ;; Moves each limb's excess, positive or negative, into the next limb, in
    ;; a copy local to this call.

    (define (carry-limbs (sums (Vector I64))) (→ (Vector I64))
      (let ((limbs (vector->array sums)))
        (let loop ((index 0) (carry 0))
          (when (< index (array-length limbs))
            (let* ((value (+ (array-ref limbs index) carry)) (low (modulo value base)))
              (array-set! limbs index low)
              (loop (+ index 1) (quotient (- value low) base)))))
        (array->vector limbs)))

    (define (integer-add (a Integer) (b Integer)) (→ Integer)
      (cond ((= (bool->sign (● a negative)) (bool->sign (● b negative)))
             (canonical (● a negative) (add-magnitudes (● a limbs) (● b limbs))))
            ((>= (compare-magnitudes (● a limbs) (● b limbs)) 0)
             (canonical (● a negative)
                        (subtract-magnitudes (● a limbs) (● b limbs))))
            (else (canonical (● b negative)
                             (subtract-magnitudes (● b limbs) (● a limbs))))))

    (define (bool->sign (negative Bool)) (→ I64)
      (if negative -1 1))

    (define (integer-subtract (a Integer) (b Integer)) (→ Integer)
      (integer-add a (integer-negate b)))

    ;; ---- Multiplication ----

    ;; Schoolbook multiplication into an array local to this call; each partial
    ;; product is carried at once so sums stay far below 2^63.

    (define (multiply-magnitudes (a (Vector I64)) (b (Vector I64))) (→ (Vector I64))
      (let ((product (make-array (+ (vector-length a) (vector-length b)) 0)))
        (vector-for-each
         (lambda (i)
           (let loop ((j 0) (carry 0))
             (if (< j (vector-length b))
                 (let ((value (+ (array-ref product (+ i j))
                                 (+ (* (vector-ref a i) (vector-ref b j)) carry))))
                   (array-set! product (+ i j) (remainder value base))
                   (loop (+ j 1) (quotient value base)))
                 (array-set! product (+ i j) (+ (array-ref product (+ i j)) carry)))))
         (list->vector (iota (vector-length a))))
        (array->vector product)))

    (define (integer-multiply (a Integer) (b Integer)) (→ Integer)
      (canonical (not (= (bool->sign (● a negative)) (bool->sign (● b negative))))
                 (multiply-magnitudes (● a limbs) (● b limbs))))

    ;; ---- Division ----

    ;; Long division, one quotient limb at a time; each limb is found by
    ;; binary search, which keeps the method obviously correct.

    (define (divide-magnitudes (a (Vector I64)) (b (Vector I64)))
      (→ (Pair (Vector I64) (Vector I64)))
      (let loop ((index (- (vector-length a) 1)) (remainder no-limbs) (quotient (Nil)))
        (if (< index 0)
            (Pair (list->vector quotient) remainder)
            (let* ((current (● (canonical #f
                                          (vector-append (vector-generate 1
                                                                          (lambda (i)
                                                                            (vector-ref
                                                                             a
                                                                             index)))
                                                         remainder)) limbs))
                   (digit (quotient-limb current b)))
              (loop (- index 1)
                    (● (canonical #f
                                  (subtract-magnitudes current
                                                       (multiply-magnitudes b
                                                                            (vector-generate
                                                                             1
                                                                             (lambda (i)
                                                                               digit))))) limbs)
                    (Cons digit quotient))))))

    ;; The largest d in [0, base) with b * d <= current.

    (define (quotient-limb (current (Vector I64)) (b (Vector I64))) (→ I64)
      (let search ((low 0) (high (- base 1)))
        (if (= low high)
            low
            (let ((middle (quotient (+ (+ low high) 1) 2)))
              (if (<= (compare-magnitudes (● (canonical #f
                                                        (multiply-magnitudes b
                                                                             (vector-generate
                                                                              1
                                                                              (lambda (i)
                                                                                middle)))) limbs)
                                          current)
                      0)
                  (search middle high)
                  (search low (- middle 1)))))))

    ;; Truncating division, as R7RS `quotient` and `remainder`.

    (define (integer-quotient (a Integer) (b Integer)) (→ Integer)
      (when (integer-zero? b) (panic "integer division by zero"))
      (canonical (not (= (bool->sign (● a negative)) (bool->sign (● b negative))))
                 (● (divide-magnitudes (● a limbs) (● b limbs)) first)))

    (define (integer-remainder (a Integer) (b Integer)) (→ Integer)
      (when (integer-zero? b) (panic "integer division by zero"))
      (canonical (● a negative)
                 (● (divide-magnitudes (● a limbs) (● b limbs)) second)))

    ;; The remainder with the sign of the divisor.

    (define (integer-modulo (a Integer) (b Integer)) (→ Integer)
      (let ((r (integer-remainder a b)))
        (if (and (not (integer-zero? r))
                 (not (= (bool->sign (● r negative)) (bool->sign (● b negative)))))
            (integer-add r b)
            r)))

    (define (integer-gcd (a Integer) (b Integer)) (→ Integer)
      (if (integer-zero? b) (integer-abs a) (integer-gcd b (integer-remainder a b))))

    (define (integer-expt (n Integer) (power I64)) (→ Integer)
      (cond ((= power 0) (integer-from-i64 1))
            ((= (remainder power 2) 0)
             (let ((half (integer-expt n (quotient power 2)))) (integer-multiply half half)))
            (else (integer-multiply n (integer-expt n (- power 1))))))

    ;; ---- Classes ----

    (instance (Num (!) Integer)
      (define + integer-add)
      (define - integer-subtract)
      (define * integer-multiply)
      (define negate integer-negate))

    (instance (Ord (!) Integer)
      (define = (lambda (a b) (= (integer-compare a b) 0)))
      (define < (lambda (a b) (< (integer-compare a b) 0)))
      (define <= (lambda (a b) (<= (integer-compare a b) 0)))
      (define > (lambda (a b) (> (integer-compare a b) 0)))
      (define >= (lambda (a b) (>= (integer-compare a b) 0))))

    (instance (Integral (!) Integer)
      (define quotient integer-quotient)
      (define remainder integer-remainder)
      (define modulo integer-modulo))

    (instance (Show (!) Integer)
      (define show integer->string))

    ))
