;; Exact integers of any size. A magnitude is a vector of base-10^9 limbs,
;; least significant first, with no high zero limbs; zero has no limbs and is
;; never negative. Every function returns canonical integers, which equality
;; and comparison rely on.
(define-library (lofi integer)
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
   (lofi base))
  (begin

    ;; ---- Representation ----

    (struct Integer
      ((negative Bool)
       (limbs (Vector I64))))

    (: base I64)
    (define base 1000000000)

    (: no-limbs (Vector I64))
    (define no-limbs (vector-generate 0 (lambda (index) 0)))

    ;; Drops high zero limbs and gives zero its one sign.
    (: canonical (-> Bool (Vector I64) Integer))
    (define (canonical negative limbs)
      (let loop ((length (vector-length limbs)))
        (cond ((= length 0) (Integer #f no-limbs))
              ((= (vector-ref limbs (- length 1)) 0) (loop (- length 1)))
              (else (Integer negative (subvector limbs 0 length))))))

    (: limb (-> (Vector I64) I64 I64))
    (define (limb limbs index)
      (if (< index (vector-length limbs)) (vector-ref limbs index) 0))

    (: integer-from-i64 (-> I64 Integer))
    (define (integer-from-i64 value)
      (if (= value -9223372036854775808)
          (integer-subtract (integer-from-i64 -9223372036854775807) (integer-from-i64 1))
          (let loop ((rest (abs value)) (limbs (Nil)))
            (if (= rest 0)
                (canonical (< value 0) (list->vector (reverse limbs)))
                (loop (quotient rest base) (Cons (remainder rest base) limbs))))))

    (: integer-zero? (-> Integer Bool))
    (define (integer-zero? n)
      (= (vector-length (Integer-limbs n)) 0))

    (: integer-negative? (-> Integer Bool))
    (define (integer-negative? n)
      (Integer-negative n))

    (: integer-negate (-> Integer Integer))
    (define (integer-negate n)
      (canonical (not (Integer-negative n)) (Integer-limbs n)))

    (: integer-abs (-> Integer Integer))
    (define (integer-abs n)
      (Integer #f (Integer-limbs n)))

    ;; ---- Conversions ----

    (: integer-fits-i64? (-> Integer Bool))
    (define (integer-fits-i64? n)
      (and (<= (integer-compare n (integer-from-i64 9223372036854775807)) 0)
           (>= (integer-compare n (integer-from-i64 -9223372036854775807)) 0)))

    ;; Wraps when the integer does not fit.
    (: integer->i64 (-> Integer I64))
    (define (integer->i64 n)
      (let ((magnitude (vector-fold (lambda (total limb) (+ (* total base) limb)) 0
                                    (reverse-vector (Integer-limbs n)))))
        (if (Integer-negative n) (negate magnitude) magnitude)))

    (: integer->f64 (-> Integer F64))
    (define (integer->f64 n)
      (let ((magnitude (vector-fold (lambda (total limb) (+ (* total 1000000000.0) (i64->f64 limb))) 0.0
                                    (reverse-vector (Integer-limbs n)))))
        (if (Integer-negative n) (negate magnitude) magnitude)))

    (: reverse-vector (-> (Vector I64) (Vector I64)))
    (define (reverse-vector items)
      (vector-generate (vector-length items) (lambda (index) (vector-ref items (- (- (vector-length items) 1) index)))))

    (: integer->string (-> Integer String))
    (define (integer->string n)
      (let ((limbs (Integer-limbs n)))
        (if (integer-zero? n)
            "0"
            (string-concatenate
             (Cons (if (Integer-negative n) "-" "")
                   (Cons (show (vector-ref limbs (- (vector-length limbs) 1)))
                         (map (lambda (index) (padded-limb (vector-ref limbs index)))
                              (reverse (iota (- (vector-length limbs) 1))))))))))

    (: padded-limb (-> I64 String))
    (define (padded-limb value)
      (let ((digits (show value)))
        (string-append (make-string (- 9 (string-length digits)) #\0) digits)))

    ;; Optional sign, then decimal digits. None if the text is not an integer.
    (: string->integer (-> String (Option Integer)))
    (define (string->integer text)
      (let* ((negative (and (> (string-length text) 0) (= (string-ref text 0) #\-)))
             (start (if (and (> (string-length text) 0) (or negative (= (string-ref text 0) #\+))) 1 0))
             (digits (substring text start (string-length text))))
        (if (and (> (string-length digits) 0) (every? char-numeric? (string->list digits)))
            (Some (canonical negative (decimal-limbs digits)))
            (None))))

    (: decimal-limbs (-> String (Vector I64)))
    (define (decimal-limbs digits)
      (let ((count (quotient (+ (string-length digits) 8) 9)))
        (vector-generate count
                         (lambda (index)
                           (let* ((end (- (string-length digits) (* 9 index))) (start (max 0 (- end 9))))
                             (fold-left (lambda (value char) (+ (* value 10) (digit-value char))) 0
                                        (string->list (substring digits start end))))))))

    ;; ---- Comparison ----

    (: compare-magnitudes (-> (Vector I64) (Vector I64) I64))
    (define (compare-magnitudes a b)
      (if (= (vector-length a) (vector-length b))
          (let loop ((index (- (vector-length a) 1)))
            (cond ((< index 0) 0)
                  ((< (vector-ref a index) (vector-ref b index)) -1)
                  ((> (vector-ref a index) (vector-ref b index)) 1)
                  (else (loop (- index 1)))))
          (if (< (vector-length a) (vector-length b)) -1 1)))

    ;; -1, 0 or 1.
    (: integer-compare (-> Integer Integer I64))
    (define (integer-compare a b)
      (cond ((and (Integer-negative a) (not (Integer-negative b))) -1)
            ((and (Integer-negative b) (not (Integer-negative a))) 1)
            ((Integer-negative a) (compare-magnitudes (Integer-limbs b) (Integer-limbs a)))
            (else (compare-magnitudes (Integer-limbs a) (Integer-limbs b)))))

    ;; ---- Addition ----

    (: add-magnitudes (-> (Vector I64) (Vector I64) (Vector I64)))
    (define (add-magnitudes a b)
      (let ((count (+ 1 (max (vector-length a) (vector-length b)))))
        (carry-limbs (vector-generate count (lambda (index) (+ (limb a index) (limb b index)))))))

    ;; Requires |a| >= |b|.
    (: subtract-magnitudes (-> (Vector I64) (Vector I64) (Vector I64)))
    (define (subtract-magnitudes a b)
      (carry-limbs (vector-generate (vector-length a) (lambda (index) (- (limb a index) (limb b index))))))

    ;; Moves each limb's excess, positive or negative, into the next limb, in
    ;; a copy local to this call.
    (: carry-limbs (-> (Vector I64) (Vector I64)))
    (define (carry-limbs sums)
      (let ((limbs (vector->array sums)))
        (let loop ((index 0) (carry 0))
          (when (< index (array-length limbs))
            (let* ((value (+ (array-ref limbs index) carry)) (low (modulo value base)))
              (array-set! limbs index low)
              (loop (+ index 1) (quotient (- value low) base)))))
        (array->vector limbs)))

    (: integer-add (-> Integer Integer Integer))
    (define (integer-add a b)
      (cond ((= (bool->sign (Integer-negative a)) (bool->sign (Integer-negative b)))
             (canonical (Integer-negative a) (add-magnitudes (Integer-limbs a) (Integer-limbs b))))
            ((>= (compare-magnitudes (Integer-limbs a) (Integer-limbs b)) 0)
             (canonical (Integer-negative a) (subtract-magnitudes (Integer-limbs a) (Integer-limbs b))))
            (else (canonical (Integer-negative b) (subtract-magnitudes (Integer-limbs b) (Integer-limbs a))))))

    (: bool->sign (-> Bool I64))
    (define (bool->sign negative)
      (if negative -1 1))

    (: integer-subtract (-> Integer Integer Integer))
    (define (integer-subtract a b)
      (integer-add a (integer-negate b)))

    ;; ---- Multiplication ----

    ;; Schoolbook multiplication into an array local to this call; each partial
    ;; product is carried at once so sums stay far below 2^63.
    (: multiply-magnitudes (-> (Vector I64) (Vector I64) (Vector I64)))
    (define (multiply-magnitudes a b)
      (let ((product (make-array (+ (vector-length a) (vector-length b)) 0)))
        (vector-for-each
         (lambda (i)
           (let loop ((j 0) (carry 0))
             (if (< j (vector-length b))
                 (let ((value (+ (array-ref product (+ i j)) (+ (* (vector-ref a i) (vector-ref b j)) carry))))
                   (array-set! product (+ i j) (remainder value base))
                   (loop (+ j 1) (quotient value base)))
                 (array-set! product (+ i j) (+ (array-ref product (+ i j)) carry)))))
         (list->vector (iota (vector-length a))))
        (array->vector product)))

    (: integer-multiply (-> Integer Integer Integer))
    (define (integer-multiply a b)
      (canonical (not (= (bool->sign (Integer-negative a)) (bool->sign (Integer-negative b))))
                 (multiply-magnitudes (Integer-limbs a) (Integer-limbs b))))

    ;; ---- Division ----

    ;; Long division, one quotient limb at a time; each limb is found by
    ;; binary search, which keeps the method obviously correct.
    (: divide-magnitudes (-> (Vector I64) (Vector I64) (Pair (Vector I64) (Vector I64))))
    (define (divide-magnitudes a b)
      (let loop ((index (- (vector-length a) 1)) (remainder no-limbs) (quotient (Nil)))
        (if (< index 0)
            (Pair (list->vector quotient) remainder)
            (let* ((current (Integer-limbs (canonical #f (vector-append (vector-generate 1 (lambda (i) (vector-ref a index))) remainder))))
                   (digit (quotient-limb current b)))
              (loop (- index 1)
                    (Integer-limbs (canonical #f (subtract-magnitudes current (multiply-magnitudes b (vector-generate 1 (lambda (i) digit))))))
                    (Cons digit quotient))))))

    ;; The largest d in [0, base) with b * d <= current.
    (: quotient-limb (-> (Vector I64) (Vector I64) I64))
    (define (quotient-limb current b)
      (let search ((low 0) (high (- base 1)))
        (if (= low high)
            low
            (let ((middle (quotient (+ (+ low high) 1) 2)))
              (if (<= (compare-magnitudes (Integer-limbs (canonical #f (multiply-magnitudes b (vector-generate 1 (lambda (i) middle))))) current) 0)
                  (search middle high)
                  (search low (- middle 1)))))))

    ;; Truncating division, as R7RS `quotient` and `remainder`.
    (: integer-quotient (-> Integer Integer Integer))
    (define (integer-quotient a b)
      (when (integer-zero? b) (panic "integer division by zero"))
      (canonical (not (= (bool->sign (Integer-negative a)) (bool->sign (Integer-negative b))))
                 (Pair-first (divide-magnitudes (Integer-limbs a) (Integer-limbs b)))))

    (: integer-remainder (-> Integer Integer Integer))
    (define (integer-remainder a b)
      (when (integer-zero? b) (panic "integer division by zero"))
      (canonical (Integer-negative a) (Pair-second (divide-magnitudes (Integer-limbs a) (Integer-limbs b)))))

    ;; The remainder with the sign of the divisor.
    (: integer-modulo (-> Integer Integer Integer))
    (define (integer-modulo a b)
      (let ((r (integer-remainder a b)))
        (if (and (not (integer-zero? r)) (not (= (bool->sign (Integer-negative r)) (bool->sign (Integer-negative b)))))
            (integer-add r b)
            r)))

    (: integer-gcd (-> Integer Integer Integer))
    (define (integer-gcd a b)
      (if (integer-zero? b) (integer-abs a) (integer-gcd b (integer-remainder a b))))

    (: integer-expt (-> Integer I64 Integer))
    (define (integer-expt n power)
      (cond ((= power 0) (integer-from-i64 1))
            ((= (remainder power 2) 0) (let ((half (integer-expt n (quotient power 2)))) (integer-multiply half half)))
            (else (integer-multiply n (integer-expt n (- power 1))))))

    ;; ---- Classes ----

    (instance (Num Integer)
      (define + integer-add)
      (define - integer-subtract)
      (define * integer-multiply)
      (define negate integer-negate))

    (instance (Ord Integer)
      (define (= a b) (= (integer-compare a b) 0))
      (define (< a b) (< (integer-compare a b) 0))
      (define (<= a b) (<= (integer-compare a b) 0))
      (define (> a b) (> (integer-compare a b) 0))
      (define (>= a b) (>= (integer-compare a b) 0)))

    (instance (Integral Integer)
      (define quotient integer-quotient)
      (define remainder integer-remainder)
      (define modulo integer-modulo))

    (instance (Show Integer)
      (define show integer->string))

    ))
