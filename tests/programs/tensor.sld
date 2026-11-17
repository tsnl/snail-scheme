;; Tensor graphs on the CPU: views that slice, transpose and broadcast
;; without a node; each kind of node evaluated; and every gradient `grad`
;; builds checked against finite differences of the evaluated loss.
(import
 (snail core base)
 (snail core io)
 (snail core table)
 (rename (snail shell tensor)
         (exp tensor-exp)
         (log tensor-log)
         (sin tensor-sin)
         (cos tensor-cos))
 (snail shell tensor eval)
 (snail shell tensor grad))

;; ---- Printing ----

(define (rounded-text (x F64)) (→ String)
  (let ((r (/ (i64->f64 (f64->i64 (round (* x 1000.0)))) 1000.0)))
    (f64->string (if (= r 0.0) 0.0 r))))

(define (show-values (label String) (values (Array F64))) (→ Unit) (! output-port)
  (write-line (string-append label ": " (string-join (map rounded-text (array->list values)) " "))))

(define (show-shape (label String) (view View)) (→ Unit) (! output-port)
  (write-line (string-append label ": " (string-join (map show (shape-of view)) "x"))))

;; ---- Inputs ----

(define (ramp (count I64) (scale F64) (shift F64)) (→ (Array F64))
  (array-generate count (lambda (i) (f32-round (+ shift (* scale (i64->f64 i)))))))

(define (f32-round (x F64)) (→ F64) (f32->f64 (f64->f32 x)))

(define (inputs-of (pairs (List (Pair String (Array F64))))) (→ (Table (Array F64)))
  (fold-left (lambda (table pair) (table-set table (● pair first) (● pair second)))
             (empty-table)
             pairs))

(define (only-value (roots (List View)) (inputs (Table (Array F64)))) (→ (Array F64))
  (list-ref (evaluate roots inputs) 0))

;; ---- Views and kinds ----

(define (views) (→ Unit) (! output-port)
  (let* ((x (param "x" (list 2 3) (Float)))
         (inputs (inputs-of (list (new Pair (first "x") (second (ramp 6 1.0 0.0)))))))
    (show-values "x" (only-value (list x) inputs))
    (show-values "transpose" (only-value (list (transpose x)) inputs))
    (show-values "narrow" (only-value (list (narrow x 1 1 2)) inputs))
    (show-values "row sums" (only-value (list (sum x (list 1))) inputs))
    (show-shape "row sums" (sum x (list 1)))
    (show-values "broadcast add" (only-value (list (+ x (param "x" (list 2 3) (Float)))) inputs))
    (show-values "column add" (only-value (list (+ x (narrow x 0 0 1))) inputs))
    (show-values "matmul" (only-value (list (matmul x (transpose x))) inputs))
    (show-values "max" (only-value (list (amax x (list 0 1))) inputs))
    (show-values "where"
                 (only-value (list (where (greater x (fill 2.5 (Nil) (Float))) x (negate x)))
                             inputs))))

(define (rows) (→ Unit) (! output-port)
  (let* ((x (param "x" (list 3 2) (Float)))
         (i (param "i" (list 4) (Unsigned)))
         (inputs (inputs-of (list (new Pair (first "x") (second (ramp 6 1.0 0.0)))
                                  (new Pair
                                    (first "i")
                                    (second (list->array (list 2.0 0.0 2.0 1.0))))))))
    (show-values "gather" (only-value (list (gather x i)) inputs))
    (show-values "scatter-add" (only-value (list (scatter-add (gather x i) i 3)) inputs))
    (show-values "scan" (only-value (list (exclusive-scan i)) inputs))
    (let ((sorted (sort-pairs i (convert (narrow (reshape x (list 6)) 0 0 4) (Unsigned)) 8)))
      (show-values "sorted keys" (only-value (list (● sorted first)) inputs))
      (show-values "sorted values" (only-value (list (● sorted second)) inputs)))
    (show-values "bytes"
                 (bytes->values (values->bytes (list->array (list 1.5 -2.0)) (Float)) (Float)))))

;; ---- Gradients ----

;; Each element of `x`'s gradient beside the central difference of the
;; loss, nudging that element.

(define (check (label String) (loss View) (x View) (inputs (Table (Array F64))))
  (→ Unit)
  (! output-port)
  (let* ((name (match (● x node kind)
                 ((Param name) name)
                 (_ (panic "check: x must be a param"))))
         (base (match (table-ref inputs name)
                 ((Some values) values)
                 ((None) (panic "check: no input"))))
         (analytic (only-value (grad loss (list x)) inputs))
         (worst (fold-left max 0.0
                           (map (lambda (k)
                                  (abs
                                   (- (array-ref analytic k) (difference loss name base k inputs))))
                                (iota (array-length base))))))
    (write-line (string-append label
                               ": "
                               (if (< worst 0.02)
                                   "agrees"
                                   (string-append "off by " (f64->string worst)))))))

(define (difference (loss View)
                    (name String)
                    (base (Array F64))
                    (k I64)
                    (inputs (Table (Array F64))))
  (→ F64)
  (let ((at (lambda (delta)
              (array-ref (only-value (list loss)
                                     (table-set inputs
                                                name
                                                (array-generate (array-length base)
                                                                (lambda (i)
                                                                  (if (= i k)
                                                                      (+ (array-ref base i) delta)
                                                                      (array-ref base i))))))
                         0)))
        (h 0.01))
    (/ (- (at h) (at (negate h))) (* 2.0 h))))

(define (gradients) (→ Unit) (! output-port)
  (let* ((x (param "x" (list 4 3) (Float)))
         (w (param "w" (list 3 2) (Float)))
         (b (param "b" (list 2) (Float)))
         (y (param "y" (list 4 2) (Float)))
         (inputs (inputs-of (list (new Pair (first "x") (second (ramp 12 0.1 -0.5)))
                                  (new Pair (first "w") (second (ramp 6 0.2 -0.4)))
                                  (new Pair (first "b") (second (ramp 2 0.5 0.1)))
                                  (new Pair (first "y") (second (ramp 8 0.3 -1.05))))))
         (fit (mean (square (- (+ (matmul x w) b) y))))
         (smooth (sum-all (* (sigmoid (matmul x w)) (tensor-exp (* (scalar 0.5) (tensor-sin b))))))
         (sliced
          (sum-all (* (narrow (transpose w) 1 1 2) (transpose (narrow (narrow x 0 0 2) 1 1 2)))))
         (picked (sum-all (absolute (- (amax (matmul x w) (list 1)) (amin y (list 1)))))))
    (check "fit dw" fit w inputs)
    (check "fit db" fit b inputs)
    (check "fit dx" fit x inputs)
    (check "smooth dw" smooth w inputs)
    (check "smooth db" smooth b inputs)
    (check "sliced dw" sliced w inputs)
    (check "sliced dx" sliced x inputs)
    (check "picked dw" picked w inputs)
    (check "picked dy" picked y inputs)
    (show-shape "fit dx" (list-ref (grad fit (list x)) 0))))

(define (rows-gradient) (→ Unit) (! output-port)
  (let* ((x (param "x" (list 3 2) (Float)))
         (i (param "i" (list 4) (Unsigned)))
         (inputs (inputs-of (list (new Pair (first "x") (second (ramp 6 0.25 -0.5)))
                                  (new Pair
                                    (first "i")
                                    (second (list->array (list 2.0 0.0 2.0 1.0)))))))
         (loss (sum-all (square (gather x i)))))
    (check "gather dx" loss x inputs)
    (show-values "gather dx" (only-value (grad loss (list x)) inputs))))

(views)
(rows)
(gradients)
(rows-gradient)
