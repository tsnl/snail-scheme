;; Elementary functions on F64, after FreeBSD's msun (fdlibm) as Rust's libm
;; crate carries it: the same polynomials, argument reductions and special
;; cases, so each result is within one ulp of the true value and equal, bit
;; for bit, to libm's (tests/programs/math). Wasm has no floating-point
;; exception flags, so the originals' arithmetic done only to raise them is
;; left out.
;;
;; ====================================================
;; Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
;; Copyright (C) 2004 by Sun Microsystems, Inc. All rights reserved. (pow)
;;
;; Developed at SunSoft, a Sun Microsystems, Inc. business.
;; Permission to use, copy, modify, and distribute this
;; software is freely granted, provided that this notice
;; is preserved.
;; ====================================================
;;
;; rust-lang/libm, https://github.com/rust-lang/compiler-builtins, is
;; available under the MIT license:
;;
;; Permission is hereby granted, free of charge, to any person obtaining a
;; copy of this software and associated documentation files (the
;; "Software"), to deal in the Software without restriction, including
;; without limitation the rights to use, copy, modify, merge, publish,
;; distribute, sublicense, and/or sell copies of the Software, and to permit
;; persons to whom the Software is furnished to do so, subject to the
;; following conditions:
;;
;; The above copyright notice and this permission notice shall be included
;; in all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
;; OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
;; NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
;; DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
;; OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
;; USE OR OTHER DEALINGS IN THE SOFTWARE.
(define-library (snail shell math)
  (export
   pi
   sin
   cos
   tan
   asin
   acos
   atan
   atan2
   exp
   log
   expt)
  (import
   (snail core base))
  (begin

    (define (pi) (→ F64) 3.141592653589793)

    ;; ---- Words ----

    ;; fdlibm reads a double through its 32-bit words. The high word holds
    ;; the sign, the exponent and the fraction's top 20 bits, so comparing
    ;; |x|'s high word with a constant compares |x| with a threshold; each
    ;; constant's hexadecimal spelling, as fdlibm writes it, is beside it.

    (define (high-word (x F64)) (→ I64)
      (i64-shift-right (f64->bits x) 32))

    (define (magnitude-word (x F64)) (→ I64)
      (i64-and (high-word x) 2147483647))

    (define (low-word (x F64)) (→ I64)
      (i64-and (f64->bits x) 4294967295))

    (define (from-words (high I64) (low I64)) (→ F64)
      (bits->f64 (i64-or (i64-shift-left (i64-and high 4294967295) 32) (i64-and low 4294967295))))

    (define (with-low-word (x F64) (low I64)) (→ F64)
      (from-words (high-word x) low))

    (define (with-high-word (x F64) (high I64)) (→ F64)
      (from-words high (low-word x)))

    ;; The sign bit, so -0.0 is negative.
    (define (negative? (x F64)) (→ Bool)
      (< (f64->bits x) 0))

    (define (magnitude (x F64)) (→ F64)
      (bits->f64 (i64-and (f64->bits x) 9223372036854775807)))

    (define (nan? (x F64)) (→ Bool)
      (not (= x x)))

    (define (signed (negative Bool) (x F64)) (→ F64)
      (if negative (negate x) x))

    (define (infinity) (→ F64)
      (bits->f64 9218868437227405312)) ; 0x7ff00000_00000000

    ;; ---- Scaling ----

    ;; 2^n for a normal exponent, -1022 <= n <= 1023.
    (define (power-of-two (n I64)) (→ F64)
      (bits->f64 (i64-shift-left (+ 1023 n) 52)))

    ;; x × 2^n. Out of the normal range it scales in up to three steps, the
    ;; last leaving n below -53 so a subnormal result is rounded only once.
    (define (scalbn (x F64) (n I64)) (→ F64)
      (cond ((> n 1023) (scale-high (* x (power-of-two 1023)) (- n 1023)))
            ((< n -1022) (scale-low (* x (power-of-two -969)) (+ n 969)))
            (else (* x (power-of-two n)))))

    (define (scale-high (x F64) (n I64)) (→ F64)
      (if (> n 1023)
          (* (* x (power-of-two 1023)) (power-of-two (min (- n 1023) 1023)))
          (* x (power-of-two n))))

    (define (scale-low (x F64) (n I64)) (→ F64)
      (if (< n -1022)
          (* (* x (power-of-two -969)) (power-of-two (max (+ n 969) -1022)))
          (* x (power-of-two n))))

    ;; ---- Argument reduction ----

    ;; x = quadrant × π/2 + (high + low), with |high + low| <~ π/4: the
    ;; remainder as two doubles, for the kernels to keep its extra bits.
    (record Reduced
      ((quadrant I64)
       (high F64)
       (low F64)))

    ;; x is finite.
    (define (reduce (x F64)) (→ Reduced)
      (let ((ix (magnitude-word x))
            (sign (if (negative? x) -1 1)))
        (cond ((<= ix 1074752122) (reduce-quarter x ix sign)) ; 0x400f6a7a, 5π/4
              ((<= ix 1075594811) (reduce-half x ix sign)) ; 0x401c463b, 9π/4
              ((< ix 1094263291) (reduce-medium x ix)) ; 0x413921fb, 2^20 π/2
              (else (reduce-large x ix sign)))))

    ;; |x| <~ 5π/4: one or two quarters off, unless x is so near a multiple
    ;; of π/2 that subtracting it cancels and the careful cut is needed.
    (define (reduce-quarter (x F64) (ix I64) (sign I64)) (→ Reduced)
      (cond ((= (i64-and ix 1048575) 598523) (reduce-medium x ix)) ; 0x921fb, π/2 or π
            ((<= ix 1073928572) (reduce-near x sign)) ; 0x4002d97c, 3π/4
            (else (reduce-near x (* 2 sign)))))

    ;; 5π/4 <~ |x| <~ 9π/4: three or four quarters, again apart from 3π/2
    ;; and 2π.
    (define (reduce-half (x F64) (ix I64) (sign I64)) (→ Reduced)
      (cond ((= ix 1074977148) (reduce-medium x ix)) ; 0x4012d97c, 3π/2
            ((= ix 1075388923) (reduce-medium x ix)) ; 0x401921fb, 2π
            ((<= ix 1075183036) (reduce-near x (* 3 sign))) ; 0x4015fdbc, 7π/4
            (else (reduce-near x (* 4 sign)))))

    ;; x − k π/2 for a small k, with π/2's first 33 bits and their tail.
    (define (reduce-near (x F64) (k I64)) (→ Reduced)
      (let* ((multiple (i64->f64 k))
             (z (- x (* multiple (pio2-1))))
             (tail (* multiple (pio2-1t)))
             (high (- z tail)))
        (new Reduced (quadrant k) (high high) (low (- (- z high) tail)))))

    (define (pio2-1) (→ F64) 1.57079632673412561417e+00) ; 0x3FF921FB, 0x54400000
    (define (pio2-1t) (→ F64) 6.07710050650619224932e-11) ; 0x3DD0B461, 0x1A626331
    (define (pio2-2) (→ F64) 6.07710050630396597660e-11) ; 0x3DD0B461, 0x1A600000
    (define (pio2-2t) (→ F64) 2.02226624879595063154e-21) ; 0x3BA3198A, 0x2E037073
    (define (pio2-3) (→ F64) 2.02226624871116645580e-21) ; 0x3BA3198A, 0x2E000000
    (define (pio2-3t) (→ F64) 8.47842766036889956997e-32) ; 0x397B839A, 0x252049C1

    ;; |x| < 2^20 π/2: n is x × 2/π rounded to an integer, and x − n π/2 is
    ;; cut in up to three rounds, each subtracting the next 33 bits of π/2
    ;; times n, until the remainder has kept enough bits.
    (define (reduce-medium (x F64) (ix I64)) (→ Reduced)
      (let* ((to-int 6755399441055744.0) ; 1.5 × 2^52: adding it rounds to an integer
             (n (- (+ (* x 6.36619772367581382433e-01) to-int) to-int)) ; 2/π
             (cut (precise-cut (new Cut (rest (- x (* n (pio2-1)))) (tail (* n (pio2-1t))))
                               n
                               (i64-shift-right ix 20)))
             (high (- (● cut rest) (● cut tail))))
        (new Reduced
          (quadrant (f64->i64 n))
          (high high)
          (low (- (- (● cut rest) high) (● cut tail))))))

    ;; x − n π/2 = rest − tail.
    (record Cut
      ((rest F64)
       (tail F64)))

    ;; Another round when the first cancelled more than 16 bits, and a third
    ;; when the second cancelled more than 49.
    (define (precise-cut (cut Cut) (n F64) (exponent I64)) (→ Cut)
      (if (> (- exponent (cut-exponent cut)) 16)
          (let ((second (cut-again cut n (pio2-2) (pio2-2t))))
            (if (> (- exponent (cut-exponent second)) 49)
                (cut-again second n (pio2-3) (pio2-3t))
                second))
          cut))

    (define (cut-again (cut Cut) (n F64) (part F64) (part-tail F64)) (→ Cut)
      (let* ((t (● cut rest))
             (w (* n part))
             (r (- t w)))
        (new Cut (rest r) (tail (- (* n part-tail) (- (- t r) w))))))

    (define (cut-exponent (cut Cut)) (→ I64)
      (i64-and (i64-shift-right (f64->bits (- (● cut rest) (● cut tail))) 52) 2047))

    ;; ---- Large arguments ----

    ;; |x| >= 2^20 π/2: Payne and Hanek's reduction, as k_rem_pio2 does it
    ;; for a double. |x| is split into up to three 24-bit integer digits,
    ;; scaled by 2^e0, and multiplied by just the digits of 2/π that can
    ;; matter at that scale; the product's integer part, mod 8, is the
    ;; quadrant, and its fraction times π/2 is the remainder.
    (define (reduce-large (x F64) (ix I64) (sign I64)) (→ Reduced)
      (let* ((z (bits->f64 (i64-or (i64-and (f64->bits x) 4503599627370495) ; 2^52 - 1
                                   (i64-shift-left (+ 1023 23) 52))))
             (first (f64->i64 z))
             (z (* (- z (i64->f64 first)) (power-of-two 24)))
             (second (f64->i64 z))
             (z (* (- z (i64->f64 second)) (power-of-two 24)))
             (reduced (reduce-digits (significant (list (i64->f64 first) (i64->f64 second) z))
                                     (- (i64-shift-right ix 20) (+ 1023 23)))))
        (if (< sign 0)
            (new Reduced
              (quadrant (negate (● reduced quadrant)))
              (high (negate (● reduced high)))
              (low (negate (● reduced low))))
            reduced)))

    ;; The digits up to the last nonzero one; the first is never zero.
    (define (significant (digits (List F64))) (→ (List F64))
      (reverse (drop-zeros (reverse digits))))

    (define (drop-zeros (digits (List F64))) (→ (List F64))
      (match digits
        ((Cons digit rest) (if (and (= digit 0.0) (not (null? rest))) (drop-zeros rest) digits))
        ((Nil) digits)))

    ;; 2/π's bits, 24 to an entry.
    (define (two-over-pi (index I64)) (→ F64)
      (if (< index 0) 0.0 (i32->f64 (constant-array-ref (two-over-pi-digits) index))))

    (define (two-over-pi-digits) (→ (ConstantArray I32))
      (constant-array I32
                      (10680707 7228996
                                1387004
                                2578385
                                16069853
                                12639074
                                9804092
                                4427841
                                16666979
                                11263675
                                12935607
                                2387514
                                4345298
                                14681673
                                3074569
                                13734428
                                16653803
                                1880361
                                10960616
                                8533493
                                3062596
                                8710556
                                7349940
                                6258241
                                3772886
                                3769171
                                3798172
                                8675211
                                12450088
                                3874808
                                9961438
                                366607
                                15675153
                                9132554
                                7151469
                                3571407
                                2607881
                                12013382
                                4155038
                                6285869
                                7677882
                                13102053
                                15825725
                                473591
                                9065106
                                15363067
                                6271263
                                9264392
                                5636912
                                4652155
                                7056368
                                13614112
                                10155062
                                1944035
                                9527646
                                15080200
                                6658437
                                6231200
                                6832269
                                16767104
                                5075751
                                3212806
                                1398474
                                7579849
                                6349435
                                12618859)))

    ;; π/2 in pieces of 24 bits.
    (define (pio2-piece (index I64)) (→ F64)
      (case index
        ((0) 1.57079625129699707031e+00) ; 0x3FF921FB, 0x40000000
        ((1) 7.54978941586159635335e-08) ; 0x3E74442D, 0x00000000
        ((2) 5.39030252995776476554e-15) ; 0x3CF84698, 0x80000000
        ((3) 3.28200341580791294123e-22) ; 0x3B78CC51, 0x60000000
        (else 1.27065575308067607349e-29))) ; 0x39F01B83, 0x80000000

    ;; ---- Large arguments: the product ----

    ;; The digits of x, from the most significant, and the offset into 2/π
    ;; where the product's digits that matter start.
    (record Product
      ((digits (Array F64))
       (offset I64)))

    (define (reduce-digits (digits (List F64)) (e0 I64)) (→ Reduced)
      (let* ((jv (max 0 (quotient (- e0 3) 24)))
             (product (new Product (digits (list->array digits)) (offset jv))))
        (distill-product product (- e0 (* 24 (+ jv 1))) 4)))

    ;; Term i of x × 2/π: the sum of each digit of x times the digit of 2/π
    ;; that lands at i. Each is exact, below 2^53.
    (define (product-term (product Product) (i I64)) (→ F64)
      (let ((digits (● product digits)))
        (fold-left (lambda (sum j)
                     (+ sum (* (array-ref digits j) (two-over-pi (+ (● product offset) (- i j))))))
                   0.0
                   (iota (array-length digits)))))

    ;; The terms 0 to jz carried into 24-bit integer digits, least
    ;; significant first, and the integer part left over, as a double.
    (record Carried
      ((digits (List I64))
       (top F64)))

    (define (carry-terms (product Product) (jz I64)) (→ Carried)
      (let loop ((j jz)
                 (z (product-term product jz))
                 (digits (Nil)))
        (if (= j 0)
            (new Carried (digits (reverse digits)) (top z))
            (let ((fw (i64->f64 (f64->i64 (* (power-of-two -24) z)))))
              (loop (- j 1)
                    (+ (product-term product (- j 1)) fw)
                    (Cons (f64->i64 (- z (* (power-of-two 24) fw))) digits))))))

    ;; ---- Large arguments: the fraction ----

    ;; After carrying, the integer part's low three bits are the quadrant and
    ;; the digits are the fraction's. Above a half, the fraction becomes one
    ;; minus itself and the quadrant one more; `flipped` keeps the sign.
    (record Fraction
      ((quadrant I64)
       (flipped Bool)
       (rest F64)
       (digits (Array I64))))

    (define (distill-product (product Product) (q0 I64) (jz I64)) (→ Reduced)
      (let ((fraction (fraction-of (carry-terms product jz) q0)))
        (match (more-terms fraction)
          ((Some more) (distill-product product q0 (+ jz more)))
          ((None) (remainder-of fraction (chop fraction q0))))))

    ;; With q0 > 0 the top digit straddles the binary point, and its bits
    ;; above it join the quadrant; the bit below it says whether the
    ;; fraction is above a half.
    (define (fraction-of (carried Carried) (q0 I64)) (→ Fraction)
      (let* ((z (scalbn (● carried top) q0))
             (z (- z (* 8.0 (floor (* z 0.125)))))
             (n (f64->i64 z))
             (rest (- z (i64->f64 n)))
             (digits (list->array (● carried digits)))
             (last (- (array-length digits) 1))
             (whole (if (> q0 0) (i64-shift-right (array-ref digits last) (- 24 q0)) 0))
             (digits (array-set digits
                                last
                                (- (array-ref digits last) (i64-shift-left whole (- 24 q0)))))
             (half (cond ((>= q0 0) (i64-shift-right (array-ref digits last) (- 23 q0)))
                         ((>= rest 0.5) 2)
                         (else 0))))
        (if (> half 0)
            (flip (+ (+ n whole) 1) half rest digits q0)
            (new Fraction (quadrant (+ n whole)) (flipped #f) (rest rest) (digits digits)))))

    ;; One minus the fraction: the digits' complement, borrowing from the
    ;; first nonzero one, with the top digit's bits above the point cleared.
    (define (flip (n I64) (half I64) (rest F64) (digits (Array I64)) (q0 I64)) (→ Fraction)
      (let* ((borrowed (array-fold (lambda (any digit) (or any (not (= digit 0)))) #f digits))
             (flipped (list->array (complement (array->list digits) #f)))
             (last (- (array-length flipped) 1))
             (flipped (case q0
                        ((1) (array-set flipped last (i64-and (array-ref flipped last) 8388607)))
                        ((2) (array-set flipped last (i64-and (array-ref flipped last) 4194303)))
                        (else flipped)))
             (rest (cond ((not (= half 2)) rest)
                         (borrowed (- (- 1.0 rest) (scalbn 1.0 q0)))
                         (else (- 1.0 rest)))))
        (new Fraction (quadrant n) (flipped #t) (rest rest) (digits flipped))))

    (define (complement (digits (List I64)) (borrowing Bool)) (→ (List I64))
      (match digits
        ((Nil) (Nil))
        ((Cons digit rest)
         (cond (borrowing (Cons (- 16777215 digit) (complement rest #t)))
               ((= digit 0) (Cons 0 (complement rest #f)))
               (else (Cons (- 16777216 digit) (complement rest #t)))))))

    ;; A fraction of zero whose digits from the fifth up are zero too may
    ;; have lost its bits to cancellation: then more terms of the product,
    ;; one for each zero digit below the fifth.
    (define (more-terms (fraction Fraction)) (→ (Option I64))
      (let ((digits (● fraction digits)))
        (if (and (= (● fraction rest) 0.0) (zero-from? digits 4))
            (Some (zeros-below digits 1))
            (None))))

    (define (zero-from? (digits (Array I64)) (index I64)) (→ Bool)
      (or (>= index (array-length digits))
          (and (= (array-ref digits index) 0) (zero-from? digits (+ index 1)))))

    (define (zeros-below (digits (Array I64)) (count I64)) (→ I64)
      (if (= (array-ref digits (- 4 count)) 0) (zeros-below digits (+ count 1)) count))

    ;; ---- Large arguments: the remainder ----

    ;; The fraction's digits, least significant first, the top one scaled by
    ;; 2^q0 and each below it by 2^-24 more.
    (record Digits
      ((digits (Array I64))
       (q0 I64)))

    ;; A zero rest leaves the digits, less any zero ones on top; otherwise
    ;; the rest, scaled back to an integer, becomes one or two more digits.
    (define (chop (fraction Fraction) (q0 I64)) (→ Digits)
      (let ((digits (● fraction digits)))
        (if (= (● fraction rest) 0.0)
            (drop-top digits (- (array-length digits) 1) (- q0 24))
            (let ((z (scalbn (● fraction rest) (negate q0))))
              (if (>= z (power-of-two 24))
                  (let ((fw (i64->f64 (f64->i64 (* (power-of-two -24) z)))))
                    (new Digits
                      (digits (array-append digits
                                            (list->array
                                             (list (f64->i64 (- z (* (power-of-two 24) fw)))
                                                   (f64->i64 fw)))))
                      (q0 (+ q0 24))))
                  (new Digits
                    (digits (array-append digits (list->array (list (f64->i64 z)))))
                    (q0 q0)))))))

    (define (drop-top (digits (Array I64)) (top I64) (q0 I64)) (→ Digits)
      (if (= (array-ref digits top) 0)
          (drop-top digits (- top 1) (- q0 24))
          (new Digits (digits (subarray digits 0 (+ top 1))) (q0 q0))))

    ;; Term m of the fraction times π/2, from the top: the pieces of π/2
    ;; times the digits from m down. The remainder is their sum, from the
    ;; least significant, and the error of that sum.
    (define (remainder-of (fraction Fraction) (scaled Digits)) (→ Reduced)
      (let* ((jz (- (array-length (● scaled digits)) 1))
             (terms (map (lambda (m) (pi-term scaled jz m)) (iota (+ jz 1))))
             (high (fold-left + 0.0 (reverse terms)))
             (low (fold-left + (- (list-ref terms 0) high) (list-tail terms 1)))
             (sign (lambda (x) (if (● fraction flipped) (negate x) x))))
        (new Reduced
          (quadrant (i64-and (● fraction quadrant) 7))
          (high (sign high))
          (low (sign low)))))

    (define (pi-term (scaled Digits) (jz I64) (m I64)) (→ F64)
      (fold-left (lambda (sum k) (+ sum (* (pio2-piece k) (digit-value scaled (+ (- jz m) k)))))
                 0.0
                 (iota (+ (min 4 m) 1))))

    (define (digit-value (scaled Digits) (index I64)) (→ F64)
      (let ((jz (- (array-length (● scaled digits)) 1)))
        (* (scalbn 1.0 (- (● scaled q0) (* 24 (- jz index))))
           (i64->f64 (array-ref (● scaled digits) index)))))

    ;; ---- Kernels ----

    ;; On [-π/4, π/4], x + y with y the tail of x: polynomials fitted to
    ;; sin, cos and tan there. `tail?` says whether y is nonzero.

    (define (kernel-sin (x F64) (y F64) (tail? Bool)) (→ F64)
      (let* ((z (* x x))
             (w (* z z))
             (r (+ (+ 8.33333333332248946124e-03 ; 0x3F811111, 0x1110F8A6
                      (* z (+ -1.98412698298579493134e-04 (* z 2.75573137070700676789e-06))))
                   (* (* z w) (+ -2.50507602534068634195e-08 (* z 1.58969099521155010221e-10)))))
             (v (* z x))
             (s1 -1.66666666666666324348e-01)) ; 0xBFC55555, 0x55555549
        (if tail?
            (- x (- (- (* z (- (* 0.5 y) (* v r))) y) (* v s1)))
            (+ x (* v (+ s1 (* z r)))))))

    (define (kernel-cos (x F64) (y F64)) (→ F64)
      (let* ((z (* x x))
             (w (* z z))
             (r (+ (* z (+ 4.16666666666666019037e-02 ; 0x3FA55555, 0x5555554C
                           (* z (+ -1.38888888888741095749e-03 (* z 2.48015872894767294178e-05)))))
                   (* (* w w)
                      (+ -2.75573143513906633035e-07
                         (* z (+ 2.08757232129817482790e-09 (* z -1.13596475577881948265e-11)))))))
             (hz (* 0.5 z))
             (w (- 1.0 hz)))
        (+ w (+ (- (- 1.0 w) hz) (- (* z r) (* x y))))))

    (define (tan-coefficient (index I64)) (→ F64)
      (case index
        ((0) 3.33333333333334091986e-01) ; 3FD55555, 55555563
        ((1) 1.33333333333201242699e-01)
        ((2) 5.39682539762260521377e-02)
        ((3) 2.18694882948595424599e-02)
        ((4) 8.86323982359930005737e-03)
        ((5) 3.59207910759131235356e-03)
        ((6) 1.45620945432529025516e-03)
        ((7) 5.88041240820264096874e-04)
        ((8) 2.46463134818469906812e-04)
        ((9) 7.81794442939557092300e-05)
        ((10) 7.14072491382608190305e-05)
        ((11) -1.85586374855275456654e-05)
        (else 2.59073051863633712884e-05))) ; BEF375CB, DB605373

    ;; tan, or -1/tan when `odd?`: an odd quadrant. Past 0.6744 the argument
    ;; becomes π/4 − x, where the polynomial converges faster.
    (define (kernel-tan (x F64) (y F64) (odd? Bool)) (→ F64)
      (let* ((big? (>= (magnitude-word x) 1072010280)) ; 0x3FE59428
             (negative (negative? x))
             (x (if big? (+ (- (pio4) (signed negative x)) (- (pio4-lo) (signed negative y))) x))
             (y (if big? 0.0 y))
             (r (tan-sum x y)))
        (cond (big? (signed negative (tan-big x r odd?)))
              (odd? (minus-reciprocal x r))
              (else (+ x r)))))

    (define (pio4) (→ F64) 7.85398163397448278999e-01) ; 3FE921FB, 54442D18
    (define (pio4-lo) (→ F64) 3.06161699786838301793e-17) ; 3C81A626, 33145C07

    ;; tan(x + y) − x: x^3 times the polynomial, split into its odd and even
    ;; terms in x^4, plus y's share.
    (define (tan-sum (x F64) (y F64)) (→ F64)
      (let* ((z (* x x))
             (w (* z z))
             (t tan-coefficient)
             (r (+ (t 1)
                   (* w (+ (t 3) (* w (+ (t 5) (* w (+ (t 7) (* w (+ (t 9) (* w (t 11))))))))))))
             (v (* z
                   (+ (t 2)
                      (* w
                         (+ (t 4) (* w (+ (t 6) (* w (+ (t 8) (* w (+ (t 10) (* w (t 12)))))))))))))
             (s (* z x)))
        (+ (+ y (* z (+ (* s (+ r v)) y))) (* s (t 0)))))

    (define (tan-big (x F64) (r F64) (odd? Bool)) (→ F64)
      (let* ((w (+ x r))
             (s (if odd? -1.0 1.0)))
        (- s (* 2.0 (+ x (- r (/ (* w w) (+ w s))))))))

    ;; -1/(x + r) to within an ulp: the quotient of the halves with their low
    ;; words zeroed, corrected.
    (define (minus-reciprocal (x F64) (r F64)) (→ F64)
      (let* ((w (+ x r))
             (w0 (with-low-word w 0))
             (v (- r (- w0 x)))
             (a (/ -1.0 w))
             (a0 (with-low-word a 0)))
        (+ a0 (* a (+ (+ 1.0 (* a0 w0)) (* a0 v))))))

    ;; ---- Trigonometry ----

    (define (sin (x F64)) (→ F64)
      (let ((ix (magnitude-word x)))
        (cond ((< ix 1045430272) x) ; 0x3e500000, |x| < 2^-26
              ((<= ix 1072243195) (kernel-sin x 0.0 #f)) ; 0x3fe921fb, π/4
              ((>= ix 2146435072) (- x x)) ; 0x7ff00000, infinity or NaN
              (else (on-quadrant (reduce x) 0)))))

    (define (cos (x F64)) (→ F64)
      (let ((ix (magnitude-word x)))
        (cond ((< ix 1044816030) 1.0) ; 0x3e46a09e, |x| < 2^-27 √2
              ((<= ix 1072243195) (kernel-cos x 0.0))
              ((>= ix 2146435072) (- x x))
              (else (on-quadrant (reduce x) 1)))))

    ;; sin of the reduced argument shifted `shift` quadrants on: cos is sin
    ;; a quadrant ahead.
    (define (on-quadrant (reduced Reduced) (shift I64)) (→ F64)
      (let ((y0 (● reduced high))
            (y1 (● reduced low)))
        (case (i64-and (+ (● reduced quadrant) shift) 3)
          ((0) (kernel-sin y0 y1 #t))
          ((1) (kernel-cos y0 y1))
          ((2) (negate (kernel-sin y0 y1 #t)))
          (else (negate (kernel-cos y0 y1))))))

    (define (tan (x F64)) (→ F64)
      (let ((ix (magnitude-word x)))
        (cond ((< ix 1044381696) x) ; 0x3e400000, |x| < 2^-27
              ((<= ix 1072243195) (kernel-tan x 0.0 #f))
              ((>= ix 2146435072) (- x x))
              (else (let ((reduced (reduce x)))
                      (kernel-tan (● reduced high)
                                  (● reduced low)
                                  (= (i64-and (● reduced quadrant) 1) 1)))))))

    ;; ---- Inverse trigonometry ----

    ;; asin(x) = x + x^3 R(x^2) near zero, with R a rational fit; further
    ;; out, asin(x) = π/2 − 2 asin(√((1 − x)/2)).

    (define (asin-ratio (z F64)) (→ F64)
      (let ((p (* z
                  (+ 1.66666666666666657415e-01 ; 0x3FC55555, 0x55555555
                     (* z
                        (+ -3.25565818622400915405e-01
                           (* z
                              (+ 2.01212532134862925881e-01
                                 (* z
                                    (+ -4.00555345006794114027e-02
                                       (* z
                                          (+ 7.91534994289814532176e-04
                                             (* z 3.47933107596021167570e-05))))))))))))
            (q (+ 1.0
                  (* z
                     (+ -2.40339491173441421878e+00 ; 0xC0033A27, 0x1C8A2D4B
                        (* z
                           (+ 2.02094576023350569471e+00
                              (* z
                                 (+ -6.88283971605453293030e-01
                                    (* z 7.70381505559019352791e-02))))))))))
        (/ p q)))

    (define (pio2-hi) (→ F64) 1.57079632679489655800e+00) ; 0x3FF921FB, 0x54442D18
    (define (pio2-lo) (→ F64) 6.12323399573676603587e-17) ; 0x3C91A626, 0x33145C07

    (define (asin (x F64)) (→ F64)
      (let ((ix (magnitude-word x)))
        (cond ((>= ix 1072693248) ; 0x3ff00000, |x| >= 1 or NaN
               (if (and (= ix 1072693248) (= (low-word x) 0)) (* x (pio2-hi)) (/ 0.0 (- x x))))
              ((< ix 1071644672) ; 0x3fe00000, |x| < 0.5
               (if (and (>= ix 1048576) (< ix 1045430272)) x (+ x (* x (asin-ratio (* x x))))))
              (else (signed (negative? x) (asin-outer (magnitude x) ix))))))

    ;; 0.5 <= x < 1. Past 0.975 the square root's rounding hardly matters;
    ;; below it, the root is split into a 32-bit head and its remainder.
    (define (asin-outer (x F64) (ix I64)) (→ F64)
      (let* ((z (* (- 1.0 x) 0.5))
             (s (sqrt z))
             (r (asin-ratio z)))
        (if (>= ix 1072640819) ; 0x3fef3333, 0.975
            (- (pio2-hi) (- (* 2.0 (+ s (* s r))) (pio2-lo)))
            (let* ((f (with-low-word s 0))
                   (c (/ (- z (* f f)) (+ s f))))
              (- (* 0.5 (pio2-hi))
                 (- (- (* (* 2.0 s) r) (- (pio2-lo) (* 2.0 c)))
                    (- (* 0.5 (pio2-hi)) (* 2.0 f))))))))

    ;; acos(x) = π/2 − asin(x) near zero; further out, 2 asin(√((1 ∓ x)/2)),
    ;; from π for negative x.
    (define (acos (x F64)) (→ F64)
      (let ((ix (magnitude-word x)))
        (cond ((>= ix 1072693248)
               (cond ((not (and (= ix 1072693248) (= (low-word x) 0))) (/ 0.0 (- x x)))
                     ((negative? x) (* 2.0 (pio2-hi)))
                     (else 0.0)))
              ((< ix 1071644672)
               (if (<= ix 1012924416) ; 0x3c600000, |x| < 2^-57
                   (pio2-hi)
                   (- (pio2-hi) (- x (- (pio2-lo) (* x (asin-ratio (* x x))))))))
              ((negative? x)
               (let* ((z (* (+ 1.0 x) 0.5))
                      (s (sqrt z)))
                 (* 2.0 (- (pio2-hi) (+ s (- (* (asin-ratio z) s) (pio2-lo)))))))
              (else (acos-positive x)))))

    (define (acos-positive (x F64)) (→ F64)
      (let* ((z (* (- 1.0 x) 0.5))
             (s (sqrt z))
             (df (with-low-word s 0))
             (c (/ (- z (* df df)) (+ s df))))
        (* 2.0 (+ df (+ (* (asin-ratio z) s) c)))))

    ;; atan(x) is reduced to a small argument through atan(x) = atan(c) +
    ;; atan((x − c)/(1 + x c)) for c of 0.5, 1, 1.5 or infinity, chosen by
    ;; |x|'s interval, then a polynomial; each atan(c) is held in two parts.
    (define (atan (x F64)) (→ F64)
      (let ((ix (magnitude-word x)))
        (cond ((>= ix 1141899264) ; 0x44100000, |x| >= 2^66 or NaN
               (if (nan? x) x (signed (negative? x) (atan-high 3))))
              ((< ix 1044381696) x) ; 0x3e400000, |x| < 2^-27
              ((< ix 1071382528) (- x (* x (atan-series x)))) ; 0x3fdc0000, 7/16
              (else (signed (negative? x) (atan-reduced (magnitude x) ix))))))

    (define (atan-reduced (x F64) (ix I64)) (→ F64)
      (cond ((< ix 1072037888) (atan-from 0 (/ (- (* 2.0 x) 1.0) (+ 2.0 x)))) ; 0x3fe60000, 11/16
            ((< ix 1072889856) (atan-from 1 (/ (- x 1.0) (+ x 1.0)))) ; 0x3ff30000, 19/16
            ((< ix 1073971200) (atan-from 2 (/ (- x 1.5) (+ 1.0 (* 1.5 x))))) ; 0x40038000, 39/16
            (else (atan-from 3 (/ -1.0 x)))))

    (define (atan-from (id I64) (x F64)) (→ F64)
      (- (atan-high id) (- (- (* x (atan-series x)) (atan-low id)) x)))

    (define (atan-high (id I64)) (→ F64)
      (case id
        ((0) 4.63647609000806093515e-01) ; atan(0.5), 0x3FDDAC67, 0x0561BB4F
        ((1) 7.85398163397448278999e-01) ; atan(1), 0x3FE921FB, 0x54442D18
        ((2) 9.82793723247329054082e-01) ; atan(1.5), 0x3FEF730B, 0xD281F69B
        (else 1.57079632679489655800e+00))) ; atan(∞), 0x3FF921FB, 0x54442D18

    (define (atan-low (id I64)) (→ F64)
      (case id
        ((0) 2.26987774529616870924e-17) ; 0x3C7A2B7F, 0x222F65E2
        ((1) 3.06161699786838301793e-17) ; 0x3C81A626, 0x33145C07
        ((2) 1.39033110312309984516e-17) ; 0x3C700788, 0x7AF0CBBD
        (else 6.12323399573676603587e-17))) ; 0x3C91A626, 0x33145C07

    ;; The sum over i of AT[i] x^(2i+2), split into odd and even powers of x^4.
    (define (atan-series (x F64)) (→ F64)
      (let* ((z (* x x))
             (w (* z z))
             (s1 (* z
                    (+ 3.33333333333329318027e-01 ; 0x3FD55555, 0x5555550D
                       (* w
                          (+ 1.42857142725034663711e-01
                             (* w
                                (+ 9.09088713343650656196e-02
                                   (* w
                                      (+ 6.66107313738753120669e-02
                                         (* w
                                            (+ 4.97687799461593236017e-02
                                               (* w 1.62858201153657823623e-02))))))))))))
             (s2 (* w
                    (+ -1.99999999998764832476e-01 ; 0xBFC99999, 0x9998EBC4
                       (* w
                          (+ -1.11111104054623557880e-01
                             (* w
                                (+ -7.69187620504482999495e-02
                                   (* w
                                      (+ -5.83357013379057348645e-02
                                         (* w -3.65315727442169155270e-02)))))))))))
        (+ s1 s2)))

    ;; atan(y/x) in the quadrant of (x, y): the special values, then atan of
    ;; |y/x| moved into the quadrant.
    (define (atan2 (y F64) (x F64)) (→ F64)
      (let ((quadrant (+ (if (negative? y) 1 0) (if (negative? x) 2 0))))
        (cond ((or (nan? x) (nan? y)) (+ x y))
              ((= x 1.0) (atan y))
              ((= y 0.0) (case quadrant ((0 1) y) ((2) (pi)) (else (negate (pi)))))
              ((= x 0.0) (signed (negative? y) (/ (pi) 2.0)))
              ((= (magnitude x) (infinity)) (atan2-infinite quadrant (= (magnitude y) (infinity))))
              (else (atan2-finite y x quadrant)))))

    (define (atan2-infinite (quadrant I64) (both? Bool)) (→ F64)
      (case quadrant
        ((0) (if both? (/ (pi) 4.0) 0.0))
        ((1) (if both? (/ (negate (pi)) 4.0) (negate 0.0)))
        ((2) (if both? (/ (* 3.0 (pi)) 4.0) (pi)))
        (else (if both? (/ (* -3.0 (pi)) 4.0) (negate (pi))))))

    ;; Past |y/x| = 2^64 the angle is ±π/2; for negative x below 2^-64 it
    ;; rounds to ±π.
    (define (atan2-finite (y F64) (x F64) (quadrant I64)) (→ F64)
      (let* ((ix (magnitude-word x))
             (iy (magnitude-word y))
             ;; 67108864 = 64 << 20: |y/x| < 2^-64 for negative x.
             (z (if (and (>= quadrant 2) (< (+ iy 67108864) ix)) 0.0 (atan (magnitude (/ y x))))))
        (cond ((or (< (+ ix 67108864) iy) (= iy 2146435072)) (signed (negative? y) (/ (pi) 2.0)))
              (else (case quadrant
                      ((0) z)
                      ((1) (negate z))
                      ((2) (- (pi) (- z (pi-lo))))
                      (else (- (- z (pi-lo)) (pi))))))))

    (define (pi-lo) (→ F64) 1.2246467991473531772e-16) ; 0x3CA1A626, 0x33145C07

    ;; ---- Exponentials and logarithms ----

    ;; exp(x) = 2^k exp(r) for x = k ln 2 + r, |r| <= ln 2 / 2, with ln 2 in
    ;; two parts so k ln 2 is exact; exp(r) comes from a rational form in r.
    (define (exp (x F64)) (→ F64)
      (let ((hx (magnitude-word x)))
        (cond ((nan? x) x)
              ((> x 709.782712893383973096) (infinity))
              ((< x -745.13321910194110842) 0.0)
              ((> hx 1071001154) (exp-reduced x hx)) ; 0x3fd62e42, ln 2 / 2
              ((> hx 1043333120) (exp-near-zero x 0.0 x 0)) ; 0x3e300000, 2^-28
              (else (+ 1.0 x)))))

    (define (exp-reduced (x F64) (hx I64)) (→ F64)
      (let* ((negative (negative? x))
             (k (cond ((>= hx 1072734898) ; 0x3ff0a2b2, 1.5 ln 2
                       ;; The nearest integer to x / ln 2.
                       (f64->i64 (+ (* 1.44269504088896338700e+00 x) (if negative -0.5 0.5))))
                      (negative -1)
                      (else 1)))
             (hi (- x (* (i64->f64 k) (ln2-hi))))
             (lo (* (i64->f64 k) (ln2-lo))))
        (exp-near-zero hi lo (- hi lo) k)))

    (define (ln2-hi) (→ F64) 6.93147180369123816490e-01) ; 0x3fe62e42, 0xfee00000
    (define (ln2-lo) (→ F64) 1.90821492927058770002e-10) ; 0x3dea39ef, 0x35793c76

    ;; 2^k exp(hi − lo), r = hi − lo.
    (define (exp-near-zero (hi F64) (lo F64) (r F64) (k I64)) (→ F64)
      (let* ((c (- r (* (* r r) (exp-series (* r r)))))
             (y (+ 1.0 (+ (- (/ (* r c) (- 2.0 c)) lo) hi))))
        (if (= k 0) y (scalbn y k))))

    (define (exp-series (t F64)) (→ F64)
      (+ 1.66666666666666019037e-01 ; 0x3FC55555, 0x5555553E
         (* t
            (+ -2.77777777770155933842e-03
               (* t
                  (+ 6.61375632143793436117e-05
                     (* t (+ -1.65339022054652515390e-06 (* t 4.13813679705723846039e-08)))))))))

    ;; log(x) = k ln 2 + log(1 + f) for x = 2^k (1 + f), √2/2 <= 1 + f < √2;
    ;; log(1 + f) comes from s = f/(2 + f) and a polynomial in s^2.
    (define (log (x F64)) (→ F64)
      (let ((hx (high-word x)))
        (cond ((< hx 1048576) ; 0x00100000: negative, zero or subnormal
               (cond ((= x 0.0) (/ -1.0 (* x x)))
                     ((negative? x) (/ (- x x) 0.0))
                     (else (log-reduced (* x (power-of-two 54)) -54))))
              ((>= hx 2146435072) x)
              ((= x 1.0) 0.0)
              (else (log-reduced x 0)))))

    (define (log-reduced (x F64) (k I64)) (→ F64)
      (let* ((hx (+ (high-word x) (- 1072693248 1072079006))) ; 0x3ff00000 − 0x3fe6a09e
             (k (+ k (- (i64-shift-right hx 20) 1023)))
             (f (- (from-words (+ (i64-and hx 1048575) 1072079006) (low-word x)) 1.0))
             (hfsq (* (* 0.5 f) f))
             (s (/ f (+ 2.0 f)))
             (dk (i64->f64 k)))
        (+ (+ (- (+ (* s (+ hfsq (log-series s))) (* dk (ln2-lo))) hfsq) f) (* dk (ln2-hi)))))

    (define (log-series (s F64)) (→ F64)
      (let* ((z (* s s))
             (w (* z z))
             (t1 (* w
                    (+ 3.999999999940941908e-01 ; 3FD99999 9997FA04
                       (* w (+ 2.222219843214978396e-01 (* w 1.531383769920937332e-01))))))
             (t2 (* z
                    (+ 6.666666666666735130e-01 ; 3FE55555 55555593
                       (* w
                          (+ 2.857142874366239149e-01
                             (* w (+ 1.818357216161805012e-01 (* w 1.479819860511658591e-01)))))))))
        (+ t2 t1)))

    ;; ---- Powers ----

    ;; x^y = 2^(y log2 x), with log2 x and the product computed in about
    ;; double the precision, as a 32-bit head and a tail. A negative x has a
    ;; real power only for an integer y, whose parity gives the sign.
    (define (expt (x F64) (y F64)) (→ F64)
      (let ((parity (integer-parity y)))
        (cond ((= y 0.0) 1.0)
              ((= x 1.0) 1.0)
              ((or (nan? x) (nan? y)) (+ x y))
              ((= (magnitude y) (infinity)) (power-infinite x y))
              ((= y 1.0) x)
              ((= y -1.0) (/ 1.0 x))
              ((= y 2.0) (* x x))
              ((and (= y 0.5) (not (negative? x))) (sqrt x))
              ((and (= (low-word x) 0) (power-exact? x)) (power-exact x y parity))
              ((and (negative? x) (= parity 0)) (/ (- x x) (- x x)))
              (else (power-general x y (if (and (negative? x) (= parity 1)) -1.0 1.0))))))

    ;; 0 when y is not an integer, 1 when odd, 2 when even, read from where
    ;; its binary point falls among its fraction bits.
    (define (integer-parity (y F64)) (→ I64)
      (let* ((iy (magnitude-word y))
             (ly (low-word y))
             (k (- (i64-shift-right iy 20) 1023)))
        (cond ((>= iy 1128267776) 2) ; 0x43400000, |y| >= 2^53
              ((< iy 1072693248) 0) ; |y| < 1
              ((> k 20) (parity-of ly (- 52 k)))
              ((= ly 0) (parity-of iy (- 20 k)))
              (else 0))))

    (define (parity-of (word I64) (shift I64)) (→ I64)
      (let ((j (i64-shift-right word shift)))
        (if (= (i64-shift-left j shift) word) (- 2 (i64-and j 1)) 0)))

    (define (power-infinite (x F64) (y F64)) (→ F64)
      (let ((ax (magnitude x)))
        (cond ((= ax 1.0) 1.0)
              ((> ax 1.0) (if (negative? y) 0.0 y))
              (else (if (negative? y) (negate y) 0.0)))))

    ;; ±0, ±1 and ±∞ have exact powers.
    (define (power-exact? (x F64)) (→ Bool)
      (let ((ix (magnitude-word x)))
        (or (= ix 2146435072) (= ix 0) (= ix 1072693248))))

    (define (power-exact (x F64) (y F64) (parity I64)) (→ F64)
      (let ((z (if (negative? y) (/ 1.0 (magnitude x)) (magnitude x))))
        (cond ((not (negative? x)) z)
              ((and (= (magnitude x) 1.0) (= parity 0)) (/ (- z z) (- z z)))
              ((= parity 1) (negate z))
              (else z))))

    ;; Beyond |y| = 2^31 the power overflows or underflows unless x is
    ;; within 2^-20 of one, where log2 x comes from its series in x − 1.
    (define (power-general (x F64) (y F64) (s F64)) (→ F64)
      (let ((ix (magnitude-word x))
            (iy (magnitude-word y))
            (up (lambda (grows) (if grows (* s (infinity)) (* s 0.0)))))
        (cond ((<= iy 1105199104) (power-of y (log2-split (magnitude x) ix) s)) ; 0x41e00000, 2^31
              ((> iy 1139802112) ; 0x43f00000, 2^64
               (if (<= ix 1072693247) (up* (negative? y)) (up* (not (negative? y)))))
              ((< ix 1072693247) (up (negative? y))) ; 0x3fefffff
              ((> ix 1072693248) (up (not (negative? y))))
              (else (power-of y (log2-near-one (magnitude x)) s)))))

    (define (up* (grows Bool)) (→ F64)
      (if grows (infinity) 0.0))

    ;; log2 x = high + low, high with its low word zero.
    (record Split
      ((high F64)
       (low F64)))

    (define (log2-near-one (ax F64)) (→ Split)
      (let* ((t (- ax 1.0))
             (w (* (* t t) (- 0.5 (* t (- 0.3333333333333333333333 (* t 0.25))))))
             (u (* 1.44269502162933349609e+00 t)) ; 0x3ff71547_60000000, 1/ln 2's 24 bits
             (v (- (* t 1.92596299112661746887e-08) (* w 1.44269504088896338700e+00)))
             (head (with-low-word (+ u v) 0)))
        (new Split (high head) (low (- v (- head u))))))

    ;; |x| = 2^n m with m in [1, √3/√2 · 2) rescaled about 1 or 1.5, the
    ;; nearer; then log2 m from s = (m − b)/(m + b) in extra precision.
    (define (log2-split (ax F64) (ix I64)) (→ Split)
      (let* ((subnormal (< ix 1048576))
             (ax (if subnormal (* ax 9007199254740992.0) ax)) ; 2^53
             (ix (if subnormal (magnitude-word ax) ix))
             (n (+ (if subnormal -53 0) (- (i64-shift-right ix 20) 1023)))
             (j (i64-and ix 1048575))
             (k (if (and (> j 235662) (< j 767610)) 1 0)) ; 0x3988E, √(3/2); 0xBB67A, √3
             (wide (>= j 767610))
             (ix (- (i64-or j 1072693248) (if wide 1048576 0))))
        (log2-of (with-high-word ax ix) ix (if wide (+ n 1) n) k)))

    (define (log2-of (ax F64) (ix I64) (n I64) (k I64)) (→ Split)
      (let* ((bp (if (= k 1) 1.5 1.0))
             (u (- ax bp))
             (v (/ 1.0 (+ ax bp)))
             (ss (* u v))
             (s-h (with-low-word ss 0))
             (t-h (from-words (+ (+ (i64-or (i64-shift-right ix 1) 536870912) 524288)
                                 (i64-shift-left k 18))
                              0))
             (t-l (- ax (- t-h bp)))
             (s-l (* v (- (- u (* s-h t-h)) (* s-h t-l)))))
        (log2-tail ss s-h s-l (i64->f64 n) k)))

    (define (log2-tail (ss F64) (s-h F64) (s-l F64) (n F64) (k I64)) (→ Split)
      (let* ((s2 (* ss ss))
             (r (+ (* (* s2 s2) (pow-log-series s2)) (* s-l (+ s-h ss))))
             (s2 (* s-h s-h))
             (t-h (with-low-word (+ (+ 3.0 s2) r) 0))
             (t-l (- r (- (- t-h 3.0) s2)))
             (u (* s-h t-h))
             (v (+ (* s-l t-h) (* t-l ss)))
             (p-h (with-low-word (+ u v) 0))
             (p-l (- v (- p-h u)))
             (z-h (* 9.61796700954437255859e-01 p-h)) ; 0x3feec709_e0000000, 2/(3 ln 2)'s head
             (z-l (+ (+ (* -7.02846165095275826516e-09 p-h) (* p-l 9.61796693925975554329e-01))
                     (if (= k 1) 1.35003920212974897128e-08 0.0))) ; log2(1.5)'s tail
             (dp-h (if (= k 1) 5.84962487220764160156e-01 0.0)) ; log2(1.5)'s head
             (t1 (with-low-word (+ (+ (+ z-h z-l) dp-h) n) 0)))
        (new Split (high t1) (low (- z-l (- (- (- t1 n) dp-h) z-h))))))

    (define (pow-log-series (s2 F64)) (→ F64)
      (+ 5.99999999999994648725e-01 ; 0x3fe33333_33333303
         (* s2
            (+ 4.28571428578550184252e-01
               (* s2
                  (+ 3.33333329818377432918e-01
                     (* s2
                        (+ 2.72728123808534006489e-01
                           (* s2
                              (+ 2.30660745775561754067e-01
                                 (* s2 2.06975017800338417784e-01)))))))))))

    ;; s × 2^(y log2 x): y split at its low word times log2 x gives
    ;; z = p-h + p-l; past 1024 it overflows and below -1075 underflows,
    ;; with OVT the rounding slack at the edge.
    (define (power-of (y F64) (log2 Split) (s F64)) (→ F64)
      (let* ((y1 (with-low-word y 0))
             (p-l (+ (* (- y y1) (● log2 high)) (* y (● log2 low))))
             (p-h (* y1 (● log2 high)))
             (z (+ p-l p-h))
             (j (high-word z))
             (i (low-word z)))
        (cond ((and (>= j 1083179008) ; 0x40900000, z >= 1024
                    (or (not (= j 1083179008))
                        (not (= i 0))
                        (> (+ p-l 8.0085662595372944372e-17) (- z p-h))))
               (* s (infinity)))
              ((and (< j 1083179008)
                    (>= (i64-and j 2147483647) 1083231232) ; 0x4090cc00, z <= -1075
                    (or (not (= (i64-and j 4294967295) 3230714880))
                        (not (= i 0))
                        (<= p-l (- z p-h))))
               (* s 0.0))
              (else (* s (two-to p-h p-l j))))))

    ;; 2^(p-h + p-l) = 2^n 2^r: n the nearest integer, taken from p-h's
    ;; bits, and 2^r from exp's rational form on r ln 2.
    (define (two-to (p-h F64) (p-l F64) (j I64)) (→ F64)
      (let* ((i (i64-and j 2147483647))
             (k (- (i64-shift-right i 20) 1023))
             ;; 0x3fe00000: |z| > 0.5, so n is nonzero.
             (n (if (> i 1071644672) (+ j (i64-shift-right 1048576 (+ k 1))) 0))
             (k (- (i64-shift-right (i64-and n 2147483647) 20) 1023))
             (whole (if (> i 1071644672)
                        (from-words (i64-and n (i64-xor (i64-shift-right 1048575 k) -1)) 0)
                        0.0))
             (n (if (> i 1071644672)
                    (let ((n (i64-shift-right (i64-or (i64-and n 1048575) 1048576) (- 20 k))))
                      (if (< j 0) (negate n) n))
                    0)))
        (scaled-exp (- p-h whole) p-l n)))

    (define (scaled-exp (p-h F64) (p-l F64) (n I64)) (→ F64)
      (let* ((t (with-low-word (+ p-l p-h) 0))
             (u (* t 6.93147182464599609375e-01)) ; 0x3fe62e43_00000000, ln 2's head
             (v (+ (* (- p-l (- t p-h)) 6.93147180559945286227e-01)
                   (* t -1.90465429995776804525e-09)))
             (z (+ u v))
             (w (- v (- z u)))
             (t (* z z))
             (t1 (- z (* t (exp-series t))))
             (r (- (/ (* z t1) (- t1 2.0)) (+ w (* z w))))
             (z (- 1.0 (- r z)))
             (j (+ (high-word z) (i64-shift-left n 20))))
        (if (<= (i64-shift-right j 20) 0) (scalbn z n) (with-high-word z j))))

    ))
