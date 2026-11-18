;; Fitting a cloud of gaussians to photographs, as 3D Gaussian Splatting
;; trains (Kerbl et al., 2023), as three tensor graphs a host compiles once
;; for a capacity of gaussians and runs on one set of params:
;;
;; - `training-step`: render from the camera param, the loss against the
;;   target param's photograph, Adam's step on every param, and the
;;   statistics densification decides by;
;; - `densification`: clone the small gaussians and split the large ones
;;   whose screen-space gradient is large, prune the transparent and the
;;   huge, and lay the cloud out again, kept rows first;
;; - `opacity-reset`: every opacity brought down to 0.01.
;;
;; Every row of every param is a gaussian; `live` says which are drawn, so
;; a cloud grows within its capacity. The schedule, when each runs and the
;; rates, is the host's; `rate-of-means` is the reference's for centers.
(define-library (snail shell graphics splat-fit)
  (export
   Stats
   stats-params
   texel-pitch
   training-step
   densification
   opacity-reset
   nearest-distances
   rate-of-means)
  (import
   (snail core base)
   (rename (snail shell tensor)
           (exp tensor-exp)
           (log tensor-log))
   (only (snail shell math) exp log)
   (snail shell tensor grad)
   (snail shell tensor adam)
   (only (snail shell graphics scan) tiles)
   (snail shell graphics splat-train)
   (snail shell graphics shaders))
  (begin

    ;; ---- Statistics ----

    ;; What densification decides by, a row a gaussian: the sum of its
    ;; screen-space gradient's length over the views that drew it, and how
    ;; many did.
    (record Stats
      ((sums View)
       (seen View)))

    (define (stats-params (count I64)) (→ Stats)
      (new Stats
        (sums (param "gradient-sums" (list count 1) (Float)))
        (seen (param "views-seen" (list count 1) (Float)))))

    (define (rows-of (view View)) (→ I64) (list-ref (shape-of view) 0))

    (define (column (a View) (k I64)) (→ View) (narrow a 1 k 1))

    ;; ---- Training ----

    ;; Texels a row of a photograph copied from a texture takes: its bytes
    ;; rounded up to 256, as a copy lays rows out.
    (define (texel-pitch (width I64)) (→ I64) (* 64 (tiles (* 4 width) 256)))

    ;; The loss, the image and the entries binned as sinks; Adam's
    ;; updates of the cloud, at the reference's rates, the centers' at the
    ;; param `rate`; and the statistics. The target param holds RGBA8
    ;; texels in rows of `texel-pitch`. A gaussian's screen-space gradient
    ;; is taken as the reference takes it, in units of half the image.
    (define (training-step (cloud Cloud) (sensor Sensor))
      (→ (Pair (List View) (List (Pair View View))))
      (let* ((width (● sensor width))
             (height (● sensor height))
             (target
              (rgba8-image (param "target" (list height (texel-pitch width)) (Unsigned)) width))
             (drawn (render cloud (camera-param) sensor))
             (loss (photometric-loss (● drawn image) target 0.2))
             (p (● drawn projection))
             (grads (grad loss (append (cloud-views cloud) (list (● p centers)))))
             (screen (list-ref grads 8))
             (spread (sqrt (+ (square (* (column screen 0) (scalar (* 0.5 (i64->f64 width)))))
                              (square (* (column screen 1) (scalar (* 0.5 (i64->f64 height))))))))
             (visible (greater (● p radii) (scalar 0.0)))
             (stats (stats-params (rows-of (● cloud means)))))
        (new Pair
          (first (list loss (● drawn image) (● drawn entries)))
          (second
           (append (adam-updates "adam" (adam 0.9 0.999 1e-15) (trained cloud (take grads 8)))
                   (list
                    (new Pair (first (● stats sums)) (second (+ (● stats sums) (* spread visible))))
                    (new Pair (first (● stats seen)) (second (+ (● stats seen) visible)))))))))

    ;; Each trained param with its gradient and rate.
    (define (trained (cloud Cloud) (grads (List View))) (→ (List Trained))
      (map (lambda (pair)
             (new Trained
               (param (● (● pair first) first))
               (grad (● pair second))
               (rate (● (● pair first) second))))
           (zip (zip (cloud-views cloud)
                     (list (param "rate" (list 1) (Float))
                           (scalar 0.005)
                           (scalar 0.001)
                           (scalar 0.025)
                           (scalar 0.0025)
                           (scalar 0.000125)
                           (scalar 0.000125)
                           (scalar 0.000125)))
                grads)))

    ;; The centers' rate at `step` of `steps`, falling exponentially from
    ;; 1.6e-4 to 1.6e-6 times the scene's extent.
    (define (rate-of-means (step I64) (steps I64) (extent F64)) (→ F64)
      (let ((t (min 1.0 (/ (i64->f64 step) (i64->f64 steps)))))
        (exp (+ (* (- 1.0 t) (log (* 0.00016 extent))) (* t (log (* 0.0000016 extent)))))))

    ;; ---- Densifying ----

    ;; The reference's decisions, a 0 or 1 a row: a live gaussian whose
    ;; mean screen-space gradient reaches 2e-4 is cloned when its largest
    ;; scale is within 1% of the scene's extent and split otherwise;
    ;; one is pruned when its opacity is under 0.005, and, once the param
    ;; `prune-big` is 1, when its scale passes a tenth of the extent. A
    ;; split one leaves its two children in its place. The paper also
    ;; prunes a gaussian drawn more than 20 pixels across, but its code
    ;; clears the radii it tests before testing them, so it never does,
    ;; and neither does gsplat by default; nor does this.
    ;;
    ;; The reference's cloud has no capacity; this one's does. Rows clone
    ;; and split in order while what they add fits in the room the rows
    ;; that stay leave, and the rest wait for a roomier program, so a full
    ;; cloud never drops a split gaussian's children.
    (record Decisions
      ((keep View)
       (clone View)
       (split View)))

    (define (decisions (cloud Cloud) (stats Stats)) (→ Decisions)
      (let* ((extent (param "extent" (list 1) (Float)))
             (one (scalar 1.0))
             (gradient (/ (● stats sums) (maximum (● stats seen) one)))
             (largest (amax (tensor-exp (● cloud scales)) (list 1)))
             (dense (* (● cloud live) (greater-equal gradient (scalar 0.0002))))
             (faint (less (sigmoid (● cloud opacities)) (scalar 0.005)))
             (huge
              (* (param "prune-big" (list 1) (Float)) (greater largest (* (scalar 0.1) extent))))
             (small (less-equal largest (* (scalar 0.01) extent)))
             (staying (* (* (● cloud live) (- one faint)) (- one huge)))
             (clone (* (* dense small) (- one faint)))
             (split (* (* dense (- one small)) (- one faint)))
             (fits (within-room (+ clone (* split (+ one huge))) staying))
             (split-fitting (* split fits)))
        (new Decisions
          (keep (* staying (- one split-fitting)))
          (clone (* clone fits))
          (split split-fitting))))

    ;; 1 for each row whose `adds`, the rows its densifying adds to those
    ;; `staying`, fit beside the adds of the rows before it. A split one
    ;; adds one, its two children for itself, or two when it is pruned as
    ;; huge, since its children are not.
    (define (within-room (adds View) (staying View)) (→ View)
      (let* ((count (rows-of adds))
             (before (reshape (convert (exclusive-scan (words adds)) (Float)) (list count 1)))
             (room (- (scalar (i64->f64 count)) (sum-all staying))))
        (less-equal (+ before adds) room)))

    (define (words (mask View)) (→ View) (convert (reshape mask (list (rows-of mask))) (Unsigned)))

    ;; For each slot of the new layout, the row it comes from and how: 1
    ;; kept, 2 cloned or a split's first child, 3 a split's second, 0 for
    ;; none (splat-place).
    (define (placement (d Decisions)) (→ (Pair View View))
      (let* ((count (rows-of (● d keep)))
             (keep (words (● d keep)))
             (fresh (words (+ (● d clone) (* (scalar 2.0) (● d split)))))
             (c (new Custom
                  (name (string-append "splat-place " (show count)))
                  (kernels (list (new Kernel
                                   (code (string-append "const CAPACITY = "
                                                        (show count)
                                                        "u;\n"
                                                        splat-place-shader))
                                   (entry "place_rows")
                                   (bindings (list 0 1 2 3 4 5))
                                   (workgroups (tiles count 256)))))
                  (adjoint (lambda (args outs) (map (lambda (_) (None)) args)))))
             (ports (custom c
                            (list keep fresh (exclusive-scan keep) (exclusive-scan fresh))
                            (list
                             (new Port (name "sources") (shape (list count)) (etype (Unsigned)))
                             (new Port (name "kinds") (shape (list count)) (etype (Unsigned)))))))
        (new Pair (first (list-ref ports 0)) (second (list-ref ports 1)))))

    ;; Six standard normal numbers a row, from the param `seed`.
    (define (normals (count I64)) (→ View)
      (list-ref (custom (new Custom
                          (name (string-append "splat-normals " (show count)))
                          (kernels (list (new Kernel
                                           (code (string-append "const COUNT = "
                                                                (show count)
                                                                "u;\n"
                                                                splat-normals-shader))
                                           (entry "sample_normals")
                                           (bindings (list 0 1))
                                           (workgroups (tiles (* 3 count) 256)))))
                          (adjoint (lambda (args outs) (list (None)))))
                        (list (param "seed" (list 1) (Unsigned)))
                        (list (new Port (name "normals") (shape (list count 6)) (etype (Float)))))
                0))

    ;; Every param, moment and mask laid out again, and the statistics
    ;; cleared; and how many gaussians are live after. A split's children take its center plus a sample of the
    ;; gaussian itself, R (s n), and its scale over 1.6; the rest of a new
    ;; gaussian is its parent's and its moments start at zero, as the
    ;; reference's do.
    (define (densification (cloud Cloud) (stats Stats)) (→ (Pair (List (Pair View View)) View))
      (let* ((d (decisions cloud stats))
             (placed (placement d))
             (sources (● placed first))
             (kinds (● placed second))
             (is (lambda (k)
                   (reshape (convert (equal kinds (fill (i64->f64 k) (Nil) (Unsigned))) (Float))
                            (list (rows-of kinds) 1))))
             (laid (lambda (kept first second)
                     (let ((zero (zeros-like kept)))
                       (where (mask-for (is 1) kept)
                              (gather kept sources)
                              (where (mask-for (is 2) kept)
                                     (gather first sources)
                                     (where (mask-for (is 3) kept)
                                            (gather second sources)
                                            zero))))))
             (children (child-means cloud (normals (rows-of (● cloud means)))))
             (split (● d split))
             (parent (lambda (view) (laid view view view)))
             (moment (lambda (view) (laid view (zeros-like view) (zeros-like view))))
             (live (maximum (is 1) (maximum (is 2) (is 3)))))
        (new Pair
          (first
           (concatenate
            (list (list (new Pair
                          (first (● cloud means))
                          (second (laid (● cloud means)
                                        (where split (● children first) (● cloud means))
                                        (● children second))))
                        (new Pair
                          (first (● cloud scales))
                          (second (let ((smaller (- (● cloud scales) (scalar (log 1.6)))))
                                    (laid (● cloud scales)
                                          (where split smaller (● cloud scales))
                                          smaller))))
                        (new Pair (first (● cloud live)) (second live)))
                  (map (lambda (view) (new Pair (first view) (second (parent view))))
                       (list-tail (cloud-views cloud) 2))
                  (concatenate (map (lambda (view)
                                      (let ((names (moment-names "adam" view)))
                                        (list (moment-update
                                               (param (● names first) (shape-of view) (Float))
                                               moment)
                                              (moment-update
                                               (param (● names second) (shape-of view) (Float))
                                               moment))))
                                    (cloud-views cloud)))
                  (map (lambda (view) (new Pair (first view) (second (zeros-like view))))
                       (list (● stats sums) (● stats seen))))))
          (second (sum-all live)))))

    (define (moment-update (view View) (laid (Fn View → View))) (→ (Pair View View))
      (new Pair (first view) (second (laid view))))

    ;; A row mask of shape (n, 1) seen in a param's shape.
    (define (mask-for (mask View) (like View)) (→ View)
      (broadcast-to
       (reshape mask (Cons (rows-of mask) (map (lambda (_) 1) (list-tail (shape-of like) 1))))
       (shape-of like)))

    ;; Each gaussian's two children's centers: its own plus R (s n) for
    ;; two samples n of the standard normal.
    (define (child-means (cloud Cloud) (n View)) (→ (Pair View View))
      (let* ((raw (● cloud rotations))
             (rotation (rotation-matrices (normalized-rows raw)))
             (scale (tensor-exp (● cloud scales)))
             (count (rows-of raw))
             (child (lambda (k)
                      (+ (● cloud means)
                         (reshape (matmul rotation (unsqueeze (* scale (narrow n 1 (* 3 k) 3)) 2))
                                  (list count 3))))))
        (new Pair (first (child 0)) (second (child 1)))))

    ;; ---- Resetting ----

    ;; Every opacity brought down to 0.01, and its moments cleared, as the
    ;; reference does every 3,000 steps.
    (define (opacity-reset (cloud Cloud)) (→ (List (Pair View View)))
      (let* ((opacities (● cloud opacities))
             (names (moment-names "adam" opacities)))
        (list (new Pair (first opacities) (second (minimum opacities (scalar (log (/ 0.01 0.99))))))
              (new Pair
                (first (param (● names first) (shape-of opacities) (Float)))
                (second (zeros-like opacities)))
              (new Pair
                (first (param (● names second) (shape-of opacities) (Float)))
                (second (zeros-like opacities))))))

    ;; ---- Starting ----

    ;; The mean squared distance from each of `points`, (n, 3), to its
    ;; three nearest others (splat-knn), which sizes the gaussians a cloud
    ;; starts with.
    (define (nearest-distances (points View)) (→ View)
      (let ((count (rows-of points)))
        (list-ref (custom (new Custom
                            (name (string-append "splat-knn " (show count)))
                            (kernels (list (new Kernel
                                             (code (string-append "const COUNT = "
                                                                  (show count)
                                                                  "u;\n"
                                                                  splat-knn-shader))
                                             (entry "nearest_three")
                                             (bindings (list 0 1))
                                             (workgroups (tiles count 256)))))
                            (adjoint (lambda (args outs) (list (None)))))
                          (list points)
                          (list (new Port (name "distances") (shape (list count)) (etype (Float)))))
                  0)))

    ))
