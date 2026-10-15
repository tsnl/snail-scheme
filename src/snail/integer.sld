;; Exact integers use private WasmGC limbs. Published arrays are immutable;
;; arithmetic owns fresh scratch storage until a canonical value is returned.
(define-library (snail integer)
  (export Integer IntegerDivision IntegerRoot
          integer-from-i64 integer->i64 integer-from-string integer->string
          integer-from-f64 integer-truncate-f64 integer->f64 integer-ratio->f64
          integer-bit-length integer-gcd integer-floor-quotient integer-modulo
          integer-zero? integer-negative? integer-abs integer-negate
          integer-compare integer=? integer<? integer<=? integer>? integer>=?
          integer-add integer-subtract integer-multiply
          integer-divide division-quotient division-remainder
          integer-quotient integer-remainder integer-expt integer-power
          integer-sqrt integer-sqrt/remainder root-value root-remainder
          + - * = < <= > >= quotient remainder)
  (import (snail strict))
  (begin

    ;; ---- Canonical magnitude and private ownership ----

    ;; A limb is in [0, 2^30). I32 stores it without a sign bit; I64 holds
    ;; products, sums and carries. Zero alone has no limbs and no negative sign.
    ;; No constructor or limb accessor is exported. Sharing in abs/negate is
    ;; safe because every published array is readonly to all library operations.
    (define radix 1073741824)
    (define limb-bits 30)
    (define-data Integer
      (integer (negative Bool integer-negative?) (limbs (Vector I32) integer-limbs)))
    (define-data IntegerDivision
      (division (quotient Integer division-quotient) (remainder Integer division-remainder)))
    (define-data IntegerRoot
      (root (value Integer root-value) (remainder Integer root-remainder)))
    (define zero (integer #f (ann (empty-vector) (Vector I32))))
    (: limb (-> (Vector I32) I64 I64))
    (define (limb digits index) (i32->i64 (vector-ref digits index)))
    (: put-limb! (-> (Vector I32) I64 I64 Unit))
    (define (put-limb! digits index value) (vector-set! digits index (i64->i32 value)))
    (: fresh-limbs (-> I64 (Vector I32)))
    (define (fresh-limbs count) (make-vector count (ann 0 I32)))
    (: significant-length (-> (Vector I32) I64))
    (define (significant-length digits)
      (let loop ((count (vector-length digits)))
        (if (or (= count 0) (not (= (limb digits (- count 1)) 0))) count
            (loop (- count 1)))))
    (: trimmed-limbs (-> (Vector I32) (Vector I32)))
    (define (trimmed-limbs digits)
      (let ((count (significant-length digits)))
        (if (= count (vector-length digits)) digits
            (let ((result (fresh-limbs count)))
              (vector-copy! result 0 digits 0 count) result))))
    (: publish (-> Bool (Vector I32) Integer))
    (define (publish negative digits)
      (let ((digits (trimmed-limbs digits)))
        (if (= (vector-length digits) 0) zero (integer negative digits))))
    (: integer-zero? (-> Integer Bool))
    (define (integer-zero? value) (= (vector-length (integer-limbs value)) 0))
    (: integer-abs (-> Integer Integer))
    (define (integer-abs value)
      (if (integer-negative? value) (integer #f (integer-limbs value)) value))
    (: integer-negate (-> Integer Integer))
    (define (integer-negate value)
      (if (integer-zero? value) value
          (integer (not (integer-negative? value)) (integer-limbs value))))

    ;; ---- Exact signed machine-integer conversion ----

    ;; Keeping the source nonpositive avoids negating I64_MIN. Each remainder
    ;; lies in (-radix, 0], so negating one limb is always representable.
    (: machine-limb-count (-> I64 I64))
    (define (machine-limb-count value)
      (let loop ((value value) (count 0))
        (if (= value 0) count (loop (quotient value radix) (+ count 1)))))
    (: integer-from-i64 (-> I64 Integer))
    (define (integer-from-i64 value)
      (let* ((negative (< value 0)) (value (if (> value 0) (- 0 value) value))
             (digits (fresh-limbs (machine-limb-count value))))
        (let loop ((value value) (index 0))
          (if (= value 0) (publish negative digits)
              (begin (put-limb! digits index (- 0 (remainder value radix)))
                     (loop (quotient value radix) (+ index 1)))))))
    (: integer->i64 (-> Integer I64))
    (define (integer->i64 value)
      (let* ((digits (integer-limbs value)) (negative (integer-negative? value))
             (limit (if negative -9223372036854775808 -9223372036854775807)))
        (let loop ((count (vector-length digits)) (result 0))
          (if (= count 0) (if negative result (- 0 result))
              (let ((digit (limb digits (- count 1))))
                ;; quotient on this negative numerator is its mathematical ceiling.
                (if (< result (quotient (+ limit digit) radix)) (unreachable)
                    (loop (- count 1) (- (* result radix) digit))))))))

    ;; ---- Magnitude order and signed comparison ----

    (: magnitude-compare (-> (Vector I32) (Vector I32) I64))
    (define (magnitude-compare left right)
      (let ((a (vector-length left)) (b (vector-length right)))
        (if (< a b) -1 (if (> a b) 1
                           (let loop ((count a))
                             (if (= count 0) 0
                                 (let ((a (limb left (- count 1))) (b (limb right (- count 1))))
                                   (if (< a b) -1 (if (> a b) 1 (loop (- count 1)))))))))))
    (: integer-compare (-> Integer Integer I64))
    (define (integer-compare left right)
      (if (not (= (if (integer-negative? left) 1 0) (if (integer-negative? right) 1 0)))
          (if (integer-negative? left) -1 1)
          (let ((order (magnitude-compare (integer-limbs left) (integer-limbs right))))
            (if (integer-negative? left) (- 0 order) order))))
    (: integer=? (-> Integer Integer Bool))
    (define (integer=? left right) (= (integer-compare left right) 0))
    (: integer<? (-> Integer Integer Bool))
    (define (integer<? left right) (< (integer-compare left right) 0))
    (: integer<=? (-> Integer Integer Bool))
    (define (integer<=? left right) (<= (integer-compare left right) 0))
    (: integer>? (-> Integer Integer Bool))
    (define (integer>? left right) (> (integer-compare left right) 0))
    (: integer>=? (-> Integer Integer Bool))
    (define (integer>=? left right) (>= (integer-compare left right) 0))

    ;; ---- Addition and subtraction expose carry and borrow ----

    (: limb-or-zero (-> (Vector I32) I64 I64))
    (define (limb-or-zero digits index)
      (if (< index (vector-length digits)) (limb digits index) 0))
    (: magnitude-add (-> (Vector I32) (Vector I32) (Vector I32)))
    (define (magnitude-add left right)
      (let* ((count (if (> (vector-length left) (vector-length right))
                        (vector-length left) (vector-length right)))
             (result (fresh-limbs (+ count 1))))
        (let loop ((index 0) (carry 0))
          (if (= index count) (begin (put-limb! result count carry) result)
              (let ((sum (+ (+ (limb-or-zero left index) (limb-or-zero right index)) carry)))
                (put-limb! result index (remainder sum radix))
                (loop (+ index 1) (quotient sum radix)))))))
    ;; left >= right is established by the signed operation before entry.
    (: magnitude-subtract (-> (Vector I32) (Vector I32) (Vector I32)))
    (define (magnitude-subtract left right)
      (let* ((count (vector-length left)) (result (fresh-limbs count)))
        (let loop ((index 0) (borrow 0))
          (if (= index count) result
              (let ((difference (- (- (limb left index) (limb-or-zero right index)) borrow)))
                (put-limb! result index (if (< difference 0) (+ difference radix) difference))
                (loop (+ index 1) (if (< difference 0) 1 0)))))))
    (: signed-difference (-> Bool (Vector I32) (Vector I32) Integer))
    (define (signed-difference negative left right)
      (if (< (magnitude-compare left right) 0)
          (publish (not negative) (magnitude-subtract right left))
          (publish negative (magnitude-subtract left right))))
    (: integer-add (-> Integer Integer Integer))
    (define (integer-add left right)
      (let ((a (integer-limbs left)) (b (integer-limbs right)))
        (if (if (integer-negative? left) (integer-negative? right) (not (integer-negative? right)))
            (publish (integer-negative? left) (magnitude-add a b))
            (signed-difference (integer-negative? left) a b))))
    (: integer-subtract (-> Integer Integer Integer))
    (define (integer-subtract left right) (integer-add left (integer-negate right)))

    ;; ---- Schoolbook products with bounded I64 accumulation ----

    ;; (B-1)^2 + (B-1) + (B-1) = B^2-1 < 2^60. Therefore each
    ;; multiply/add/carry transition is exact before division by B. A row's
    ;; final carry goes into a previously untouched output position.
    (: multiply-row! (-> (Vector I32) (Vector I32) I64 I64 Unit))
    (define (multiply-row! result right offset factor)
      (let ((count (vector-length right)))
        (let loop ((index 0) (carry 0))
          (if (= index count) (put-limb! result (+ offset count) carry)
              (let* ((at (+ offset index))
                     (product (+ (+ (* factor (limb right index)) (limb result at)) carry)))
                (put-limb! result at (remainder product radix))
                (loop (+ index 1) (quotient product radix)))))))
    (: magnitude-multiply (-> (Vector I32) (Vector I32) (Vector I32)))
    (define (magnitude-multiply left right)
      (let ((result (fresh-limbs (+ (vector-length left) (vector-length right)))))
        (let loop ((index 0))
          (if (= index (vector-length left)) result
              (begin (multiply-row! result right index (limb left index))
                     (loop (+ index 1)))))))
    (: integer-multiply (-> Integer Integer Integer))
    (define (integer-multiply left right)
      (if (or (integer-zero? left) (integer-zero? right)) zero
          (publish (if (integer-negative? left) (not (integer-negative? right))
                       (integer-negative? right))
                   (magnitude-multiply (integer-limbs left) (integer-limbs right)))))
    ;; factor is positive and below B. Keeping one extra limb is sufficient.
    (: magnitude-scale (-> (Vector I32) I64 (Vector I32)))
    (define (magnitude-scale digits factor)
      (let* ((count (vector-length digits)) (result (fresh-limbs (+ count 1))))
        (let loop ((index 0) (carry 0))
          (if (= index count) (begin (put-limb! result count carry) result)
              (let ((product (+ (* (limb digits index) factor) carry)))
                (put-limb! result index (remainder product radix))
                (loop (+ index 1) (quotient product radix)))))))

    ;; ---- Single-limb division ----

    ;; A private quotient buffer may alias its source: traversal is high to low,
    ;; and each old limb is consumed before its slot is overwritten. The caller
    ;; never passes a published limb array as target. Return the scalar remainder.
    (: divide-small! (-> (Vector I32) (Vector I32) I64 I64))
    (define (divide-small! target source divisor)
      (let loop ((count (vector-length source)) (carry 0))
        (if (= count 0) carry
            (let ((value (+ (* carry radix) (limb source (- count 1)))))
              (put-limb! target (- count 1) (quotient value divisor))
              (loop (- count 1) (remainder value divisor))))))

    ;; ---- Normalized long division ----

    ;; Knuth's normalization makes the highest divisor limb >= B/2.
    ;; The two-high-limb estimate is never low and at most two high. Checking
    ;; the next limb reduces that error to at most one; full subtraction decides
    ;; the last correction. Every numerator/product is below B^2 = 2^60.
    (: estimate-digit (-> (Vector I32) (Vector I32) I64 I64))
    (define (estimate-digit dividend divisor offset)
      (let* ((count (vector-length divisor)) (high (limb divisor (- count 1)))
             (numerator (+ (* (limb dividend (+ offset count)) radix)
                           (limb dividend (- (+ offset count) 1))))
             (trial (quotient numerator high)) (trial (if (>= trial radix) (- radix 1) trial)))
        (let correct ((trial trial) (residue (- numerator (* trial high))))
          (if (and (< residue radix)
                   (> (* trial (limb divisor (- count 2)))
                      (+ (* residue radix) (limb dividend (- (+ offset count) 2)))))
              (correct (- trial 1) (+ residue high)) trial))))
    ;; Trial, divisor digit and incoming carry are in [0, B-1]. Thus
    ;; product <= B*(B-1) < 2^60: masking and logical shifting split it exactly.
    ;; If its high word is B-1, product must be B*(B-1), so its low word is
    ;; zero and subtraction cannot borrow. Otherwise high+borrow <= B-1 too.
    ;; The low difference lies in (-B, B); adding B restores one limb.
    (: subtract-product! (-> (Vector I32) (Vector I32) I64 I64 Bool))
    (define (subtract-product! dividend divisor offset trial)
      (let ((count (vector-length divisor)))
        (let loop ((index 0) (carry 0))
          (if (= index count)
              (let ((high (- (limb dividend (+ offset count)) carry)))
                (when (or (< high -1) (> high 0)) (unreachable))
                (put-limb! dividend (+ offset count) (if (< high 0) (+ high radix) high))
                (< high 0))
              (let* ((product (+ (* trial (limb divisor index)) carry))
                     (difference (- (limb dividend (+ offset index))
                                    (i64-bitwise-and product (- radix 1)))))
                (put-limb! dividend (+ offset index) (if (< difference 0) (+ difference radix) difference))
                (loop (+ index 1) (+ (i64-shift-right/logical product limb-bits)
                                     (if (< difference 0) 1 0))))))))
    (: add-back! (-> (Vector I32) (Vector I32) I64 Unit))
    (define (add-back! dividend divisor offset)
      (let ((count (vector-length divisor)))
        (let loop ((index 0) (carry 0))
          (if (= index count)
              (put-limb! dividend (+ offset count)
                         (remainder (+ (limb dividend (+ offset count)) carry) radix))
              (let ((sum (+ (+ (limb dividend (+ offset index)) (limb divisor index)) carry)))
                (put-limb! dividend (+ offset index) (remainder sum radix))
                (loop (+ index 1) (quotient sum radix)))))))
    (: divide-position! (-> (Vector I32) (Vector I32) I64 I64))
    (define (divide-position! dividend divisor offset)
      (let ((trial (estimate-digit dividend divisor offset)))
        (if (subtract-product! dividend divisor offset trial)
            (begin (add-back! dividend divisor offset) (- trial 1)) trial)))
    (: divide-normalized! (-> (Vector I32) (Vector I32) (Vector I32) Unit))
    (define (divide-normalized! quotient-digits dividend divisor)
      (let loop ((count (vector-length quotient-digits)))
        (unless (= count 0)
          (put-limb! quotient-digits (- count 1) (divide-position! dividend divisor (- count 1)))
          (loop (- count 1)))))
    (: long-division (-> (Vector I32) (Vector I32) IntegerDivision))
    (define (long-division left right)
      (let* ((count (vector-length right))
             (scale (quotient radix (+ (limb right (- count 1)) 1)))
             (dividend (magnitude-scale left scale))
             (divisor (trimmed-limbs (magnitude-scale right scale)))
             (answer (fresh-limbs (+ (- (vector-length left) count) 1)))
             (residue (fresh-limbs count)))
        (divide-normalized! answer dividend divisor)
        (vector-copy! residue 0 dividend 0 count)
        (unless (= (divide-small! residue residue scale) 0) (unreachable))
        (division (publish #f answer) (publish #f residue))))
    (: divide-magnitudes (-> Integer Integer IntegerDivision))
    (define (divide-magnitudes left right)
      (let ((a (integer-limbs left)) (b (integer-limbs right)))
        (if (< (magnitude-compare a b) 0) (division zero (integer-abs left))
            (if (= (vector-length b) 1)
                (let* ((answer (fresh-limbs (vector-length a)))
                       (residue (divide-small! answer a (limb b 0))))
                  (division (publish #f answer) (integer-from-i64 residue)))
                (long-division a b)))))
    (: integer-divide (-> Integer Integer IntegerDivision))
    (define (integer-divide left right)
      (if (integer-zero? right) (unreachable)
          (let* ((result (divide-magnitudes left right))
                 (q (division-quotient result)) (r (division-remainder result)))
            (division (if (if (integer-negative? left) (not (integer-negative? right))
                              (integer-negative? right)) (integer-negate q) q)
                      (if (integer-negative? left) (integer-negate r) r)))))
    (: integer-quotient (-> Integer Integer Integer))
    (define (integer-quotient left right) (division-quotient (integer-divide left right)))
    (: integer-remainder (-> Integer Integer Integer))
    (define (integer-remainder left right) (division-remainder (integer-divide left right)))

    ;; ---- Decimal text with independent mutable strings ----

    ;; Nine decimal digits fit in a limb. Grouped conversion does one linear
    ;; magnitude pass per chunk, rather than one per character. ASCII signs and
    ;; digits only are accepted; empty input, whitespace and prefixes trap.
    (: decimal-chunk (-> String I64 I64 I64))
    (define (decimal-chunk text start end)
      (let loop ((index start) (value 0))
        (if (= index end) value
            (let ((digit (- (char->integer (string-ref text index)) 48)))
              (if (or (< digit 0) (> digit 9)) (unreachable)
                  (loop (+ index 1) (+ (* value 10) digit)))))))
    (: machine-power (-> I64 I64 I64))
    (define (machine-power base exponent)
      (let loop ((left exponent) (value 1))
        (if (= left 0) value (loop (- left 1) (* value base)))))
    (: parse-decimal (-> String I64 Bool Integer))
    (define (parse-decimal text start negative)
      (let ((count (string-length text)))
        (if (= start count) (unreachable)
            (let loop ((at start) (value zero))
              (if (= at count) (if negative (integer-negate value) value)
                  (let* ((width (if (> (- count at) 9) 9 (- count at)))
                         (scaled (publish #f (magnitude-scale (integer-limbs value) (machine-power 10 width))))
                         (chunk (integer-from-i64 (decimal-chunk text at (+ at width)))))
                    (loop (+ at width) (integer-add scaled chunk))))))))
    (: integer-from-string (-> String Integer))
    (define (integer-from-string text)
      (if (= (string-length text) 0) (unreachable)
          (let* ((first (string-ref text 0)) (negative (char=? first #\-))
                 (signed (or negative (char=? first #\+))))
            (parse-decimal text (if signed 1 0) negative))))
    (: decimal-chunks (-> (Vector I32) (List I64)))
    (define (decimal-chunks digits)
      (let loop ((digits (vector-copy digits)) (chunks '()))
        (if (= (vector-length digits) 0) chunks
            (let ((chunk (divide-small! digits digits 1000000000)))
              (loop (trimmed-limbs digits) (cons chunk chunks))))))
    (: decimal-width (-> I64 I64))
    (define (decimal-width value)
      (let loop ((value value) (count 1))
        (if (< value 10) count (loop (quotient value 10) (+ count 1)))))
    (: chunk-count (-> (List I64) I64))
    (define (chunk-count chunks)
      (let loop ((tail chunks) (count 0))
        (if (null? tail) count (loop (cdr tail) (+ count 1)))))
    (: write-chunk! (-> String I64 I64 I64 Unit))
    (define (write-chunk! text end value width)
      (let loop ((at end) (left width) (value value))
        (unless (= left 0)
          (string-set! text (- at 1) (integer->char (+ 48 (remainder value 10))))
          (loop (- at 1) (- left 1) (quotient value 10)))))
    (: write-chunks! (-> String I64 (List I64) I64 Unit))
    (define (write-chunks! text at chunks width)
      (unless (null? chunks)
        (write-chunk! text (+ at width) (car chunks) width)
        (write-chunks! text (+ at width) (cdr chunks) 9)))
    (: integer->string (-> Integer String))
    (define (integer->string value)
      (if (integer-zero? value) (string #\0)
          (let* ((chunks (decimal-chunks (integer-limbs value)))
                 (width (decimal-width (car chunks))) (sign (if (integer-negative? value) 1 0))
                 (text (make-string (+ (+ sign width) (* 9 (- (chunk-count chunks) 1))))))
            (when (integer-negative? value) (string-set! text 0 #\-))
            (write-chunks! text sign chunks width) text)))

    ;; ---- Nonnegative exponentiation and floor square root ----

    (: half (-> Integer Integer))
    (define (half value)
      (let* ((digits (integer-limbs value)) (result (fresh-limbs (vector-length digits))))
        (divide-small! result digits 2) (publish #f result)))
    (: integer-expt (-> Integer Integer Integer))
    (define (integer-expt base exponent)
      (if (integer-negative? exponent) (unreachable)
          (let loop ((power base) (left exponent) (result (integer-from-i64 1)))
            (if (integer-zero? left) result
                (let ((result (if (= (remainder (limb (integer-limbs left) 0) 2) 0) result
                                  (integer-multiply result power)))
                      (left (half left)))
                  (if (integer-zero? left) result
                      (loop (integer-multiply power power) left result)))))))
    (: integer-power (-> Integer I64 Integer))
    (define (integer-power base exponent) (integer-expt base (integer-from-i64 exponent)))
    (: leading-bits (-> I64 I64))
    (define (leading-bits value)
      (let loop ((value value) (count 0))
        (if (= value 0) count (loop (quotient value 2) (+ count 1)))))
    (: sqrt-upper-bound (-> Integer Integer))
    (define (sqrt-upper-bound value)
      (let* ((digits (integer-limbs value)) (count (vector-length digits))
             (bits (+ (* (- count 1) limb-bits) (leading-bits (limb digits (- count 1)))))
             (exponent (quotient (+ bits 1) 2)) (at (quotient exponent limb-bits))
             (result (fresh-limbs (+ at 1))))
        (put-limb! result at (machine-power 2 (remainder exponent limb-bits)))
        (publish #f result)))
    (: integer-sqrt (-> Integer Integer))
    (define (integer-sqrt value)
      (if (integer-negative? value) (unreachable)
          (if (integer-zero? value) value
              (let loop ((estimate (sqrt-upper-bound value)))
                (let ((next (half (integer-add estimate (integer-quotient value estimate)))))
                  ;; Starting above the root makes every accepted estimate decrease.
                  ;; At floor(sqrt(n)), the next estimate can be larger (n=3).
                  (if (integer>=? next estimate) estimate (loop next)))))))
    (: integer-sqrt/remainder (-> Integer IntegerRoot))
    (define (integer-sqrt/remainder value)
      (let ((root-value (integer-sqrt value)))
        (root root-value (integer-subtract value (integer-multiply root-value root-value)))))

    ;; ---- Exact conversion from finite binary64 integers ----

    ;; Division by the power-of-two limb radix is exact. Once the quotient is
    ;; truncated, cancellation recovers an integer digit smaller than the radix.
    ;; Negative zero maps to the unique exact zero. Fractional/nonfinite inputs
    ;; are rejected; the separately named truncating conversion is explicit.
    (: finite-f64? (-> F64 Bool))
    (define (finite-f64? value)
      (and (= value value) (< value (/ 1.0 0.0)) (> value (/ -1.0 0.0))))
    (: float-limb-count (-> F64 I64))
    (define (float-limb-count value)
      (let loop ((value value) (count 0))
        (if (= value 0.0) count
            (loop (truncate (/ value (i64->f64 radix))) (+ count 1)))))
    (: integer-from-f64 (-> F64 Integer))
    (define (integer-from-f64 value)
      (if (not (and (finite-f64? value) (= value (truncate value)))) (unreachable)
          (let* ((negative (< value 0.0)) (value (if negative (- 0.0 value) value))
                 (digits (fresh-limbs (float-limb-count value))) (base (i64->f64 radix)))
            (let loop ((value value) (at 0))
              (if (= value 0.0) (publish negative digits)
                  (let ((next (truncate (/ value base))))
                    (put-limb! digits at (f64->i64 (- value (* next base))))
                    (loop next (+ at 1))))))))
    (: integer-truncate-f64 (-> F64 Integer))
    (define (integer-truncate-f64 value) (integer-from-f64 (truncate value)))

    ;; ---- One nearest-even rounding from an exact ratio to binary64 ----

    ;; Choose the final binary64 spacing before dividing. The quotient retains
    ;; at most 53 bits; its exact remainder decides rounding once, including
    ;; halfway cases, subnormals, signed underflow and overflow to infinity.
    (: integer-bit-length (-> Integer I64))
    (define (integer-bit-length value)
      (let* ((digits (integer-limbs value)) (count (vector-length digits)))
        (if (= count 0) 0
            (+ (* (- count 1) limb-bits) (leading-bits (limb digits (- count 1)))))))
    (: binary-power (-> I64 Integer))
    (define (binary-power exponent) (integer-power (integer-from-i64 2) exponent))
    (: binary64-power (-> I64 F64))
    (define (binary64-power exponent)
      (let ((factor (if (< exponent 0) 0.5 2.0))
            (count (if (< exponent 0) (- 0 exponent) exponent)))
        (let loop ((left count) (value 1.0))
          (if (= left 0) value (loop (- left 1) (* value factor))))))
    (: ratio-below-power? (-> Integer Integer I64 Bool))
    (define (ratio-below-power? numerator denominator exponent)
      (if (< exponent 0)
          (integer<? (integer-multiply numerator (binary-power (- 0 exponent))) denominator)
          (integer<? numerator (integer-multiply denominator (binary-power exponent)))))
    (: rounded-ratio (-> Integer Integer I64))
    (define (rounded-ratio numerator denominator)
      (let* ((answer (integer-divide numerator denominator))
             (whole (integer->i64 (division-quotient answer)))
             (twice (integer-add (division-remainder answer) (division-remainder answer)))
             (order (integer-compare twice denominator)))
        (if (or (> order 0) (and (= order 0) (= (remainder whole 2) 1))) (+ whole 1) whole)))
    (: scaled-ratio (-> Integer Integer I64 F64))
    (define (scaled-ratio numerator denominator spacing)
      (let ((whole (if (< spacing 0)
                       (rounded-ratio (integer-multiply numerator (binary-power (- 0 spacing))) denominator)
                       (rounded-ratio numerator (integer-multiply denominator (binary-power spacing))))))
        (* (i64->f64 whole) (binary64-power spacing))))
    (: positive-ratio->f64 (-> Integer Integer F64))
    (define (positive-ratio->f64 numerator denominator)
      (let ((estimate (- (integer-bit-length numerator) (integer-bit-length denominator))))
        (if (> estimate 1024) (/ 1.0 0.0)
            (if (< estimate -1075) 0.0
                (let ((exponent (if (ratio-below-power? numerator denominator estimate) (- estimate 1) estimate)))
                  (if (> exponent 1023) (/ 1.0 0.0)
                      (scaled-ratio numerator denominator
                                    (if (< exponent -1022) -1074 (- exponent 52)))))))))
    (: integer-ratio->f64 (-> Integer Integer F64))
    (define (integer-ratio->f64 numerator denominator)
      (if (integer-zero? denominator) (unreachable)
          (if (integer-zero? numerator) 0.0
              (let ((value (positive-ratio->f64 (integer-abs numerator) (integer-abs denominator))))
                (if (if (integer-negative? numerator) (not (integer-negative? denominator))
                        (integer-negative? denominator)) (* -1.0 value) value)))))
    (: integer->f64 (-> Integer F64))
    (define (integer->f64 value) (integer-ratio->f64 value (integer-from-i64 1)))

    ;; ---- Euclidean reduction and floor division ----

    (: integer-gcd (-> Integer Integer Integer))
    (define (integer-gcd left right)
      (let loop ((left (integer-abs left)) (right (integer-abs right)))
        (if (integer-zero? right) left (loop right (integer-remainder left right)))))
    (: integer-floor-quotient (-> Integer Integer Integer))
    (define (integer-floor-quotient left right)
      (let ((answer (integer-divide left right)))
        (if (and (not (integer-zero? (division-remainder answer)))
                 (if (integer-negative? left) (not (integer-negative? right)) (integer-negative? right)))
            (integer-subtract (division-quotient answer) (integer-from-i64 1))
            (division-quotient answer))))
    (: integer-modulo (-> Integer Integer Integer))
    (define (integer-modulo left right)
      (integer-subtract left (integer-multiply right (integer-floor-quotient left right))))

    ;; ---- Ordinary static numeric methods ----

    (define-overload + (-> Integer Integer Integer) integer-add)
    (define-overload - (-> Integer Integer Integer) integer-subtract)
    (define-overload - (-> Integer Integer) integer-negate)
    (define-overload * (-> Integer Integer Integer) integer-multiply)
    (define-overload = (-> Integer Integer Bool) integer=?)
    (define-overload < (-> Integer Integer Bool) integer<?)
    (define-overload <= (-> Integer Integer Bool) integer<=?)
    (define-overload > (-> Integer Integer Bool) integer>?)
    (define-overload >= (-> Integer Integer Bool) integer>=?)
    (define-overload quotient (-> Integer Integer Integer) integer-quotient)
    (define-overload remainder (-> Integer Integer Integer) integer-remainder))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-integer)
    (begin
      ;; The runner also instantiates this same arithmetic at radix 4. Its
      ;; exhaustive oracle uses bounded machine arithmetic, independently of
      ;; quotient estimation and correction. No test exposes mutable limbs.
      (define (test-product-carry)
        ;; (B-1)*B^2 - (B-1)*(B^2-1) = B-1. The first digit borrows;
        ;; the next product reaches B*(B-1), where another borrow is impossible.
        (let ((dividend (fresh-limbs 3)) (divisor (fresh-limbs 2)))
          (put-limb! dividend 2 (- radix 1))
          (put-limb! divisor 0 (- radix 1))
          (put-limb! divisor 1 (- radix 1))
          (unless (and (not (subtract-product! dividend divisor 0 (- radix 1)))
                       (= (limb dividend 0) (- radix 1))
                       (= (limb dividend 1) 0) (= (limb dividend 2) 0))
            (unreachable))))
      (define (test-integer)
        (test-product-carry)
        (let numerator ((a 0))
          (if (= a 1024) 42
              (begin
                (let denominator ((b 1))
                  (unless (= b 64)
                    (let* ((left (integer-from-i64 a)) (right (integer-from-i64 b))
                           (answer (integer-divide left right)))
                      (unless (and (= (integer->i64 (division-quotient answer)) (quotient a b))
                                   (= (integer->i64 (division-remainder answer)) (remainder a b))
                                   (= (integer->i64 (integer-add left right)) (+ a b))
                                   (= (integer->i64 (integer-subtract left right)) (- a b))
                                   (= (integer->i64 (integer-multiply left right)) (* a b)))
                        (unreachable)))
                    (denominator (+ b 1))))
                (numerator (+ a 1))))))))))
