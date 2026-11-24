;; Tensor graphs on the CPU: views that slice, transpose and broadcast
;; without a node; each kind of node evaluated; every gradient `grad`
;; builds checked against finite differences of the evaluated loss; and
;; fused graphs, which compute exactly what they fused.
(import
 (snail core base)
 (snail core io)
 (snail core table)
 (only (snail shell math) half-bits)
 (rename (snail shell tensor)
         (exp tensor-exp)
         (log tensor-log)
         (sin tensor-sin)
         (cos tensor-cos))
 (snail shell tensor eval)
 (snail shell tensor grad)
 (snail shell tensor fuse))

;; ---- Printing ----

(define (rounded-text (x F64)) (→ String)
  (let ((r (/ (i64->f64 (f64->i64 (round (* x 1000.0)))) 1000.0)))
    (f64->string (if (= r 0.0) 0.0 r))))

(define (show-values (out OutputPort) (label String) (values (Array F64))) (→ Unit)
  (write-line out
              (string-append label ": " (string-join (map rounded-text (array->list values)) " "))))

(define (show-shape (out OutputPort) (label String) (view View)) (→ Unit)
  (write-line out (string-append label ": " (string-join (map show (shape-of view)) "x"))))

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

;; Reusing the caller's upload bytes and label must preserve both constants.
(define (constants (out OutputPort)) (→ Unit)
  (let* ((bytes (values->bytes (list->array (list 2.0)) (Signed)))
         (a (constant "weight" (Nil) (Signed) bytes)))
    (array-set! bytes 0 (i32->u8 5))
    (let ((b (constant "weight" (Nil) (Signed) bytes)))
      (show-values out "constants" (only-value (list (stack (list a b) 0)) (empty-table))))))

(define (views (out OutputPort)) (→ Unit)
  (let* ((x (param "x" (list 2 3) (Float)))
         (inputs (inputs-of (list (new Pair (first "x") (second (ramp 6 1.0 0.0)))))))
    (show-values out "x" (only-value (list x) inputs))
    (show-values out "transpose" (only-value (list (transpose x)) inputs))
    (show-values out "narrow" (only-value (list (narrow x 1 1 2)) inputs))
    (show-values out "row sums" (only-value (list (sum x (list 1))) inputs))
    (show-shape out "row sums" (sum x (list 1)))
    (show-values out
                 "broadcast add"
                 (only-value (list (+ x (param "x" (list 2 3) (Float)))) inputs))
    (show-values out "column add" (only-value (list (+ x (narrow x 0 0 1))) inputs))
    (show-values out "matmul" (only-value (list (matmul x (transpose x))) inputs))
    (show-values out "max" (only-value (list (amax x (list 0 1))) inputs))
    (show-values out "where"
                 (only-value (list (where (greater x (fill 2.5 (Nil) (Float))) x (negate x)))
                             inputs))
    (show-values out "concat" (only-value (list (concat (list x (narrow x 1 0 1)) 1)) inputs))
    (show-shape out "stack" (stack (list x x x) 2))))

(define (rows (out OutputPort)) (→ Unit)
  (let* ((x (param "x" (list 3 2) (Float)))
         (i (param "i" (list 4) (Unsigned)))
         (inputs (inputs-of (list (new Pair (first "x") (second (ramp 6 1.0 0.0)))
                                  (new Pair
                                    (first "i")
                                    (second (list->array (list 2.0 0.0 2.0 1.0))))))))
    (show-values out "gather" (only-value (list (gather x i)) inputs))
    (show-values out "scatter-add" (only-value (list (scatter-add (gather x i) i 3)) inputs))
    (show-values out "scan" (only-value (list (exclusive-scan i)) inputs))
    (let ((sorted (sort-pairs i (convert (narrow (reshape x (list 6)) 0 0 4) (Unsigned)) 8)))
      (show-values out "sorted keys" (only-value (list (● sorted first)) inputs))
      (show-values out "sorted values" (only-value (list (● sorted second)) inputs)))
    (show-values out "bytes"
                 (bytes->values (values->bytes (list->array (list 1.5 -2.0)) (Float)) (Float)))))

;; Floats rounded to binary16 two to a u32, low half first, and read back
;; by `halves`: rounding to even, the largest half, ties past it to
;; infinity, subnormals, and under half the smallest, zero.
(define (halves-line (out OutputPort)) (→ Unit)
  (let* ((floats (list 1.0
                       -2.0
                       0.1
                       65504.0
                       65519.0
                       65520.0
                       1e5
                       5.960464477539063e-8
                       2.9802322387695312e-8
                       4.5e-8
                       6.103515625e-5
                       0.333333
                       (negate 0.0)
                       0.0))
         (bits (map (lambda (x) (half-bits (f64->f32 x))) floats))
         (words (map (lambda (j)
                       (i64->f64 (i64-or (list-ref bits (* 2 j))
                                         (i64-shift-left (list-ref bits (+ (* 2 j) 1)) 16))))
                     (iota 7)))
         (w (param "words" (list 7) (Unsigned)))
         (inputs (inputs-of (list (new Pair (first "words") (second (list->array words)))))))
    (write-line out
                (string-append "halves: "
                               (string-join (map f64->string
                                                 (array->list
                                                  (only-value (list (halves w)) inputs)))
                                            " ")))))

;; ---- Gradients ----

;; Each element of `x`'s gradient beside the central difference of the
;; loss, nudging that element.

(define (check (out OutputPort) (label String) (loss View) (x View) (inputs (Table (Array F64))))
  (→ Unit)
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
    (write-line out (string-append label
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

(define (gradients (out OutputPort)) (→ Unit)
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
         (picked (sum-all (absolute (- (amax (matmul x w) (list 1)) (amin y (list 1))))))
         (stacked (sum-all (square (concat (list (narrow w 1 0 1)
                                                 (* w (narrow w 1 1 1))
                                                 (transpose (narrow x 0 0 2)))
                                           1)))))
    (check out "fit dw" fit w inputs)
    (check out "fit db" fit b inputs)
    (check out "fit dx" fit x inputs)
    (check out "smooth dw" smooth w inputs)
    (check out "smooth db" smooth b inputs)
    (check out "sliced dw" sliced w inputs)
    (check out "sliced dx" sliced x inputs)
    (check out "picked dw" picked w inputs)
    (check out "picked dy" picked y inputs)
    (check out "stacked dw" stacked w inputs)
    (check out "stacked dx" stacked x inputs)
    (check out "tiled dx" (sum-all (square (gram (narrow x 0 0 2)))) x inputs)
    (check out "filled dw" (sum-all (square (matmul (fill 0.5 (list 4 3) (Float)) w))) w inputs)
    (show-shape out "fit dx" (list-ref (grad fit (list x)) 0))))

(define (rows-gradient (out OutputPort)) (→ Unit)
  (let* ((x (param "x" (list 3 2) (Float)))
         (i (param "i" (list 4) (Unsigned)))
         (inputs (inputs-of (list (new Pair (first "x") (second (ramp 6 0.25 -0.5)))
                                  (new Pair
                                    (first "i")
                                    (second (list->array (list 2.0 0.0 2.0 1.0)))))))
         (loss (sum-all (square (gather x i)))))
    (check out "gather dx" loss x inputs)
    (show-values out "gather dx" (only-value (grad loss (list x)) inputs))))

;; Views that read no elements hand back no share: an empty slice beside
;; a one-element one at the same offset, and a slice of an empty port.
(define (empty-gradients (out OutputPort)) (→ Unit)
  (let* ((x (param "x" (list 3) (Float)))
         (e (param "e" (list 0 3) (Float)))
         (inputs (inputs-of (list (new Pair (first "x") (second (ramp 3 1.0 0.0)))
                                  (new Pair (first "e") (second (ramp 0 1.0 0.0))))))
         (beside (+ (sum-all (narrow x 0 0 0)) (sum-all (narrow x 0 0 1))))
         (de (list-ref (grad (sum-all (narrow e 1 1 1)) (list e)) 0)))
    (show-values out "empty beside one dx" (only-value (grad beside (list x)) inputs))
    (write-line out
                (string-append "empty port dx: "
                               (string-join (map show (shape-of de)) "x")
                               ", "
                               (show (array-length (only-value (list de) inputs)))
                               " values"))))

;; A body of several operations differentiated as one expression: a
;; row's elements picked apart, combined, and packed again, whose gradient
;; is one map; and a map of two ports, the loss reading one of them, whose
;; other adds nothing, then both.
(define (expression-gradients (out OutputPort)) (→ Unit)
  (let* ((x (param "x" (list 4 3) (Float)))
         (inputs (inputs-of (list (new Pair (first "x") (second (ramp 12 0.1 -0.5))))))
         (row (Load 0 (Float) (list 3)))
         (at (lambda (i) (Apply (Pick (list i)) (list row) (Float) (Nil))))
         (k (lambda (c) (Literal c (Float))))
         (of (lambda (op a) (Apply op (list a) (Float) (Nil))))
         (on (lambda (op a b) (Apply op (list a b) (Float) (Nil))))
         (u (at 0))
         (v (at 1))
         (w (at 2))
         (body (Apply (Pack)
                      (list (k 0.0)
                            (on (Mul) (k 1.5) (on (Mul) u v))
                            (on (Sub) (on (Mul) w w) (of (Sqrt) (on (Add) (on (Mul) u u) (k 1.0))))
                            (on (Div) (of (Exp) v) (on (Add) (on (Mul) w w) (k 2.0)))
                            (on (Max) u (on (Mul) v w)))
                      (Float)
                      (list 5)))
         (one (mapped body (list x) (list 4)))
         (two (mapped-ports (list body (on (Mul) u (of (Sin) w))) (list x) (list 4)))
         (first-port (node-view two (map-port-name 0)))
         (second-port (node-view two (map-port-name 1)))
         (loss (sum-all (square one))))
    (check out "one map dx" loss x inputs)
    (check out "two ports, one read, dx" (sum-all (square first-port)) x inputs)
    (check out "two ports dx" (+ (sum-all (square first-port)) (sum-all second-port)) x inputs)
    (write-line out
                (string-append "one map dx: "
                               (show (length (toposort (grad loss (list x)))))
                               " nodes, "
                               (show (length (toposort (list loss))))
                               " in the loss"))))

;; ---- Fusion ----

;; A fused graph computes exactly what it fused, since the evaluator rounds
;; each operation as the GPU does, with the nodes it needs left.

(define (fused-line (out OutputPort) (label String) (root View) (inputs (Table (Array F64))))
  (→ Unit)
  (let* ((fused (list-ref (fuse (list root)) 0))
         (same (every? (lambda (pair) (= (● pair first) (● pair second)))
                       (zip (array->list (only-value (list root) inputs))
                            (array->list (only-value (list fused) inputs))))))
    (write-line out (string-append label
                                   ": "
                                   (show (length (toposort (list root))))
                                   " nodes, fused "
                                   (show (length (toposort (list fused))))
                                   (if same ", the same values" ", other values")))))

(define (fusion (out OutputPort)) (→ Unit)
  (let* ((x (param "x" (list 2 3) (Float)))
         (inputs (inputs-of (list (new Pair (first "x") (second (ramp 6 0.25 -0.5)))))))
    (fused-line out "chain" (tensor-exp (+ (* x (scalar 2.0)) (scalar 1.0))) inputs)
    (fused-line out "transposed" (+ (transpose (* x x)) (scalar 1.0)) inputs)
    (fused-line out "narrowed" (* (narrow (tensor-exp x) 1 1 2) (scalar 3.0)) inputs)
    (fused-line out
                "broadcast"
                (* x (broadcast-to (tensor-exp (narrow x 1 0 1)) (list 2 3)))
                inputs)
    (fused-line out "converted"
                (convert
                 (* (convert (greater x (scalar 0.0)) (Unsigned)) (fill 3.0 (Nil) (Unsigned)))
                 (Float))
                inputs)
    (fused-line out "merged" (* (reshape (tensor-exp (transpose x)) (list 6)) (scalar 2.0)) inputs)
    (fused-line out "reduced" (sum (tensor-exp x) (list 1)) inputs)
    (fused-line out "across" (sum (tensor-exp x) (list 0)) inputs)
    (fused-line out "product" (matmul (tensor-exp x) (transpose (* x x))) inputs)
    (fused-line out "shared" (+ (tensor-exp x) (* (tensor-exp x) (tensor-exp x))) inputs)
    (fused-line out "tiled" (gram x) inputs)
    (fused-line out "picked"
                (* (narrow (reshape (gram x) (list 2 9)) 1 4 1) (narrow (tensor-exp x) 1 0 1))
                inputs)
    (let ((wide (param "wide" (list 2 20) (Float))))
      (fused-line out "kept"
                  (kept-once wide)
                  (inputs-of (list (new Pair (first "wide") (second (ramp 40 0.05 -1.0)))))))
    (let ((a (param "a" (list 2 3 3) (Float)))
          (b (param "b" (list 2 3 3) (Float))))
      (fused-line out "picked thrice"
                  (picked-thrice a b)
                  (inputs-of (list (new Pair (first "a") (second (ramp 18 0.1 -0.9)))
                                   (new Pair (first "b") (second (ramp 18 -0.05 0.4)))))))))

;; Each row's tile of three packed rows, scaled by the row, times its
;; transpose: a pack, a map and a product of tiles, which fuse into one
;; kernel, each thread computing its row's 3 x 3 tile.
(define (gram (x View)) (→ View)
  (let* ((rows (concat (list (tensor-exp x) (* x x) (+ x (scalar 1.0))) 1))
         (m (* (reshape rows (list 2 3 3)) (unsqueeze x 1))))
    (matmul m (transpose m))))

;; A sum of two reductions that two kernels read is written once: taking
;; it into both would keep both reductions' buffers alive until the second.
;; Their spans of 20 are too long to fold as tiles.
(define (kept-once (x View)) (→ View)
  (let ((p (+ (sum (* x x) (list 1)) (amax x (list 1)))))
    (+ (tensor-exp p) (sum (* p x) (list 1)))))

;; A product of two params that three kernels each pick one element of is
;; written once: taking it into each would read both params' tiles in all
;; three, more than its own kernel reads and writes. A concat along the
;; first axis keeps the three kernels apart.
(define (picked-thrice (a View) (b View)) (→ View)
  (let ((p (reshape (matmul a b) (list 2 9))))
    (concat
     (list (tensor-exp (narrow p 1 0 1)) (square (narrow p 1 4 1)) (absolute (narrow p 1 8 1)))
     0)))

;; Eight params summed: a kernel binds at most seven buffers besides its
;; port, so the sum is two maps.
(define (fusion-limits (out OutputPort)) (→ Unit)
  (let* ((names (map (lambda (k) (string-append "p" (show k))) (iota 8)))
         (ps (map (lambda (name) (param name (list 4) (Float))) names))
         (inputs (inputs-of (map-indexed (lambda (k name)
                                           (new Pair
                                             (first name)
                                             (second (ramp 4 1.0 (i64->f64 k)))))
                                         names))))
    (fused-line out "eight params" (fold-left + (list-ref ps 0) (list-drop ps 1)) inputs)))

;; Updates whose maps read each other's values whole, as Adam's do, fused:
;; the map reading the others writes them too, so their ports are one
;; kernel's. Read in another order, a value keeps its own kernel.
(define (written-ports (out OutputPort)) (→ Unit)
  (let* ((names (list "p" "m" "v" "g"))
         (ps (map (lambda (name) (param name (list 4 3) (Float))) names))
         (p (list-ref ps 0))
         (m (list-ref ps 1))
         (v (list-ref ps 2))
         (g (list-ref ps 3))
         (inputs (inputs-of (map-indexed (lambda (k name)
                                           (new Pair
                                             (first name)
                                             (second (ramp 12 0.05 (* 0.1 (i64->f64 k))))))
                                         names)))
         (m2 (+ (* (scalar 0.9) m) (* (scalar 0.1) g)))
         (v2 (+ (* (scalar 0.999) v) (* (scalar 0.001) (square g))))
         (p2 (- p (/ (* (scalar 0.01) m2) (+ (sqrt v2) (scalar 1e-8)))))
         (turned (concat (list (narrow m2 0 2 2) (narrow m2 0 0 2)) 0)))
    (updates-line out
                  "adam"
                  (list (new Pair (first m) (second m2))
                        (new Pair (first v) (second v2))
                        (new Pair (first p) (second p2)))
                  inputs)
    (updates-line out
                  "reordered"
                  (list (new Pair (first m) (second m2)) (new Pair (first g) (second (- g turned))))
                  inputs)
    (later-line out m g inputs)))

;; A map reading a producer whole, which a gather after it reads too: the
;; map writes the producer's port, which the gather then reads.
(define (later-line (out OutputPort) (m View) (g View) (inputs (Table (Array F64)))) (→ Unit)
  (let* ((shared (+ (* m m) g))
         (sum (+ shared (scalar 1.0)))
         (rows (gather shared
                       (constant "rows"
                                 (list 2)
                                 (Unsigned)
                                 (values->bytes (list->array (list 3.0 0.0)) (Unsigned)))))
         (roots (list sum rows))
         (fused (fuse roots))
         (same (every? (lambda (pair)
                         (every? (lambda (xy) (= (● xy first) (● xy second)))
                                 (zip (array->list (● pair first)) (array->list (● pair second)))))
                       (zip (evaluate roots inputs) (evaluate fused inputs)))))
    (write-line out (string-append "read later: "
                                   (show (length (toposort roots)))
                                   " nodes, fused "
                                   (show (length (toposort fused)))
                                   ", the map of "
                                   (show (length (● (list-ref fused 0) node ports)))
                                   " ports"
                                   (if same ", the same values" ", other values")))))

;; How many nodes the updates' values need before and after fusing, the
;; ports of the node computing the last, and whether they agree.
(define (updates-line (out OutputPort)
                      (label String)
                      (updates (List (Pair View View)))
                      (inputs (Table (Array F64))))
  (→ Unit)
  (let* ((fused (● (fuse-program (Nil) updates) second))
         (values (lambda (us) (map (lambda (u) (● u second)) us)))
         (same (every? (lambda (pair)
                         (every? (lambda (xy) (= (● xy first) (● xy second)))
                                 (zip (array->list (● pair first)) (array->list (● pair second)))))
                       (zip (evaluate (values updates) inputs) (evaluate (values fused) inputs))))
         (last (list-ref (values fused) (- (length fused) 1))))
    (write-line out (string-append label
                                   ": "
                                   (show (length (toposort (values updates))))
                                   " nodes, fused "
                                   (show (length (toposort (values fused))))
                                   ", the last of "
                                   (show (length (● last node ports)))
                                   " ports"
                                   (if same ", the same values" ", other values")))))

(define (main (out OutputPort)) (→ Unit)
  (constants out)
  (views out)
  (rows out)
  (halves-line out)
  (gradients out)
  (rows-gradient out)
  (empty-gradients out)
  (expression-gradients out)
  (fusion out)
  (fusion-limits out)
  (written-ports out)
  (unit))
