;; (snail shell math) against Rust's libm crate, the fdlibm port it follows:
;; each function at chosen inputs, then a checksum of its results over a
;; sweep of generated ones. The expected output is libm's, printed by
;; crates/snail-scheme-support/examples/math-reference, which draws the same
;; inputs.
(import
 (snail core base)
 (snail core io)
 (snail shell math))

(define (specials) (→ (List F64))
  (list 0.0
        (negate 0.0)
        1.0
        -1.0
        0.5
        -0.5
        2.0
        3.0
        0.1
        1e-10
        5e-324
        2.2250738585072014e-308
        1.5707963267948966
        3.141592653589793
        10.0
        100.0
        1e6
        1e22
        1e300
        1.7976931348623157e308
        -1e22
        1647100.0
        3400000.5
        7000001.25
        16777215.75
        1e15
        5.319372648326541e255
        8.98846567431158e307
        -2.5e100
        (/ 1.0 0.0)
        (/ -1.0 0.0)
        (/ 0.0 0.0)))

(define (exponents) (→ (List F64))
  (list 0.0 (negate 0.0) 1.0 -1.0 0.5 2.0 3.0 -3.0 (/ 1.0 0.0) (/ 0.0 0.0)))

;; ---- Sweeps ----

;; Park and Miller's generator, x' = 48271 x mod (2^31 − 1), and the inputs
;; drawn from it: any double, from 31 high bits, 31 low bits and a sign, or
;; one uniform in (−range, range).
(define (draw (seed I64)) (→ I64)
  (modulo (* seed 48271) 2147483647))

(record Drawn
  ((value F64)
   (seed I64)))

(define (any-double (seed I64)) (→ Drawn)
  (let* ((high (draw seed))
         (low (draw high))
         (sign (draw low))
         (value (bits->f64 (i64-or (i64-shift-left high 32) (i64-shift-left low 1)))))
    (new Drawn (value (if (= (modulo sign 2) 0) value (negate value))) (seed sign))))

(define (within (seed I64) (range F64)) (→ Drawn)
  (let ((next (draw seed)))
    (new Drawn (value (* (- (* (/ (i64->f64 next) 2147483647.0) 2.0) 1.0) range)) (seed next))))

;; Each result's words, or 1 for any NaN, whose bits Wasm leaves open.
(define (mix (hash I64) (value F64)) (→ I64)
  (let ((step (lambda (hash word) (modulo (+ (* hash 31) word) 2147483647)))
        (bits (f64->bits value)))
    (if (= value value)
        (step (step hash (i64-and (i64-shift-right bits 32) 4294967295)) (i64-and bits 4294967295))
        (step hash 1))))

(define (unary-sweep (f (Fn F64 → F64)) (range F64) (seed I64) (hash I64) (count I64)) (→ I64)
  (if (= count 0)
      hash
      (let* ((any (any-double seed))
             (near (within (● any seed) range)))
        (unary-sweep f
                     range
                     (● near seed)
                     (mix (mix hash (f (● any value))) (f (● near value)))
                     (- count 1)))))

(define (binary-sweep (f (Fn F64 F64 → F64)) (range F64) (seed I64) (hash I64) (count I64))
  (→ I64)
  (if (= count 0)
      hash
      (let* ((x (any-double seed))
             (y (any-double (● x seed)))
             (u (within (● y seed) range))
             (v (within (● u seed) range)))
        (binary-sweep f
                      range
                      (● v seed)
                      (mix (mix hash (f (● x value) (● y value))) (f (● u value) (● v value)))
                      (- count 1)))))

;; ---- Reports ----

(define (unary (name String) (f (Fn F64 → F64)) (range F64)) (→ Unit) (! output-port)
  (for-each (lambda (x) (write-line (string-join (list name (show x) (show (f x))) " ")))
            (specials))
  (write-line (string-append name
                             " sweep "
                             (show (unary-sweep f range (+ (string-length name) 1) 0 20000)))))

(define (binary (name String) (f (Fn F64 F64 → F64)) (range F64)) (→ Unit) (! output-port)
  (for-each (lambda (x)
              (for-each (lambda (y)
                          (write-line
                           (string-join (list name (show x) (show y) (show (f x y))) " ")))
                        (exponents)))
            (specials))
  (write-line (string-append name
                             " sweep "
                             (show (binary-sweep f range (+ (string-length name) 1) 0 20000)))))

(define (main) (→ Unit) (! output-port)
  (unary "sin" sin 1e3)
  (unary "cos" cos 1e3)
  (unary "tan" tan 1e3)
  (unary "asin" asin 1.0)
  (unary "acos" acos 1.0)
  (unary "atan" atan 1e3)
  (unary "exp" exp 800.0)
  (unary "log" log 1e3)
  (binary "atan2" atan2 1e3)
  (binary "expt" expt 30.0))
