;; Gaussian splatting as a differentiable tensor graph, the renderer 3DGS
;; training descends through (Kerbl et al., 2023): `render` draws a cloud
;; of gaussian params from a camera param into an image, and `grad`
;; differentiates the loss of that image back to every param.
;;
;;   (let* ((cloud (splat-params 100000))
;;          (drawn (render cloud (camera-param) (new Sensor (width 1237) (height 822) (capacity 4000000))))
;;          (loss (photometric-loss (● drawn image) (param "target" (list 822 1237 3) (Float)) 0.2)))
;;     (grad loss (cloud-views cloud)))
;;
;; Projection is ordinary tensor operations, so `grad` derives its
;; gradient: each gaussian's rotation and scale make its covariance, the
;; camera carries it to the screen linearized at its center (EWA), and its
;; spherical harmonics give its color from the camera's eye. Binning
;; gaussians into 16x16-pixel tiles is custom kernels around a sort by
;; depth and a stable sort by tile (splat-tiles, splat-count, splat-keys,
;; splat-ranges), and passes no gradient. Rasterizing is a custom node
;; (splat-forward) whose adjoint is another (splat-backward). SSIM's window
;; is a custom blur (splat-blur), its own adjoint.
;;
;; The camera is a param of 16 floats: the world-to-camera rotation's rows,
;; its translation, then fx, fy, cx, cy, in COLMAP's convention, the camera
;; looking down +z with +y down the image and pixel (x, y) centered at
;; (x + 0.5, y + 0.5).
(define-library (snail shell graphics splat-train)
  (export
   Cloud
   splat-params
   cloud-views
   Sensor
   camera-param
   Projection
   project
   Rendering
   render
   blur
   ssim
   photometric-loss
   rgba8-image)
  (import
   (snail core base)
   (rename (snail shell tensor)
           (exp tensor-exp))
   (only (snail shell math) exp)
   (only (snail shell graphics scan) tiles)
   (snail shell graphics shaders))
  (begin

    ;; ---- Params ----

    ;; A cloud's params, each a row a gaussian: its center; the logarithm
    ;; of its scale on each axis; its rotation, a quaternion x y z w not
    ;; yet normalized; its opacity's logit; and its spherical harmonics'
    ;; coefficients by degree, 1, 3, 5 and 7 of them for each of red, green
    ;; and blue. Those are trained. `live` is 1 for a gaussian drawn and 0
    ;; for a row not yet used, and `degrees` 1 or 0 for whether each
    ;; degree from 1 to 3 shades, which a schedule raises.
    (record Cloud
      ((means View)
       (scales View)
       (rotations View)
       (opacities View)
       (dc View)
       (degree1 View)
       (degree2 View)
       (degree3 View)
       (live View)
       (degrees View)))

    (define (splat-params (count I64)) (→ Cloud)
      (new Cloud
        (means (param "means" (list count 3) (Float)))
        (scales (param "scales" (list count 3) (Float)))
        (rotations (param "rotations" (list count 4) (Float)))
        (opacities (param "opacities" (list count 1) (Float)))
        (dc (param "dc" (list count 1 3) (Float)))
        (degree1 (param "degree1" (list count 3 3) (Float)))
        (degree2 (param "degree2" (list count 5 3) (Float)))
        (degree3 (param "degree3" (list count 7 3) (Float)))
        (live (param "live" (list count 1) (Float)))
        (degrees (param "degrees" (list 3) (Float)))))

    ;; The params a cloud trains.
    (define (cloud-views (cloud Cloud)) (→ (List View))
      (list (● cloud means)
            (● cloud scales)
            (● cloud rotations)
            (● cloud opacities)
            (● cloud dc)
            (● cloud degree1)
            (● cloud degree2)
            (● cloud degree3)))

    ;; The image drawn and how many tile entries binning holds; entries
    ;; past it are dropped.
    (record Sensor
      ((width I64)
       (height I64)
       (capacity I64)))

    (define (camera-param) (→ View) (param "camera" (list 16) (Float)))

    (define (column (a View) (k I64)) (→ View) (narrow a 1 k 1))

    (define (camera-scalar (camera View) (k I64)) (→ View) (narrow camera 0 k 1))

    ;; ---- Projection ----

    ;; What the rasterizer draws a gaussian by: its center in pixels, its
    ;; conic, color and opacity, and for binning its depth and radius in
    ;; pixels, 0 when culled.
    (record Projection
      ((centers View)
       (conics View)
       (colors View)
       (opacities View)
       (depths View)
       (radii View)))

    (define (project (cloud Cloud) (camera View) (sensor Sensor)) (→ Projection)
      (let* ((rotation (reshape (narrow camera 0 0 9) (list 3 3)))
             (seen (+ (matmul (● cloud means) (transpose rotation)) (narrow camera 0 9 3)))
             (depth (column seen 2))
             (near (maximum depth (scalar 0.2)))
             (screen (screen-covariance (covariance cloud) rotation seen near camera sensor))
             (conic (conic-of screen))
             (visible (* (greater depth (scalar 0.2)) (greater (● conic second) (scalar 0.0)))))
        (new Projection
          (centers (concat (list (+ (* (camera-scalar camera 12) (/ (column seen 0) near))
                                    (camera-scalar camera 14))
                                 (+ (* (camera-scalar camera 13) (/ (column seen 1) near))
                                    (camera-scalar camera 15)))
                           1))
          (conics (● conic first))
          (colors (shaded cloud camera))
          (opacities (sigmoid (● cloud opacities)))
          (depths near)
          (radii (* (* visible (● cloud live)) (radius screen (● conic second)))))))

    ;; An unused row can have a zero quaternion and sit exactly at the eye.
    ;; Bound its squared norm before sqrt so both the row and its gradient
    ;; stay finite.
    (define (normalized-rows (v View)) (→ View)
      (/ v (sqrt (maximum (sum (square v) (list 1)) (scalar 1e-24)))))

    ;; R S S^T R^T, each gaussian's rotation from its normalized
    ;; quaternion, its scale the exponent of its param.
    (define (covariance (cloud Cloud)) (→ View)
      (let* ((q (normalized-rows (● cloud rotations)))
             (m (* (rotation-matrices q) (unsqueeze (tensor-exp (● cloud scales)) 1))))
        (matmul m (transpose m))))

    (define (rotation-matrices (q View)) (→ View)
      (let ((x (column q 0))
            (y (column q 1))
            (z (column q 2))
            (w (column q 3))
            (one (scalar 1.0))
            (two (scalar 2.0)))
        (reshape (concat (list (- one (* two (+ (* y y) (* z z))))
                               (* two (- (* x y) (* w z)))
                               (* two (+ (* x z) (* w y)))
                               (* two (+ (* x y) (* w z)))
                               (- one (* two (+ (* x x) (* z z))))
                               (* two (- (* y z) (* w x)))
                               (* two (- (* x z) (* w y)))
                               (* two (+ (* y z) (* w x)))
                               (- one (* two (+ (* x x) (* y y)))))
                         1)
                 (list (list-ref (shape-of q) 0) 3 3))))

    ;; J W Sigma W^T J^T, the Jacobian J of the pinhole at each center,
    ;; with the center's slope clamped to 1.3 times the field of view, as
    ;; the reference does, and 0.3 pixels^2 added to the diagonal: a
    ;; gaussian's (a, b, c) on the screen.
    (define (screen-covariance (sigma View)
                               (rotation View)
                               (seen View)
                               (near View)
                               (camera View)
                               (sensor Sensor))
      (→ View)
      (let* ((fx (camera-scalar camera 12))
             (fy (camera-scalar camera 13))
             (count (list-ref (shape-of seen) 0))
             (zero (zeros-like near))
             (x (* near
                   (clamped (/ (column seen 0) near)
                            (/ (scalar (* 0.65 (i64->f64 (● sensor width)))) fx))))
             (y (* near
                   (clamped (/ (column seen 1) near)
                            (/ (scalar (* 0.65 (i64->f64 (● sensor height)))) fy))))
             (jacobian (reshape (concat (list (/ (broadcast-to fx (shape-of near)) near)
                                              zero
                                              (negate (/ (* fx x) (* near near)))
                                              zero
                                              (/ (broadcast-to fy (shape-of near)) near)
                                              (negate (/ (* fy y) (* near near))))
                                        1)
                                (list count 2 3)))
             (t (matmul jacobian (broadcast-to rotation (list count 3 3))))
             (cov (reshape (matmul (matmul t sigma) (transpose t)) (list count 4))))
        (concat
         (list (+ (column cov 0) (scalar 0.3)) (column cov 1) (+ (column cov 3) (scalar 0.3)))
         1)))

    (define (clamped (a View) (limit View)) (→ View)
      (minimum (maximum a (negate limit)) limit))

    ;; The inverse of (a b; b c) as (a, b, c), and its determinant.
    (define (conic-of (screen View)) (→ (Pair View View))
      (let* ((a (column screen 0))
             (b (column screen 1))
             (c (column screen 2))
             (det (- (* a c) (* b b)))
             (safe (maximum det (scalar 1e-12))))
        (new Pair
          (first (concat (list (/ c safe) (negate (/ b safe)) (/ a safe)) 1))
          (second det))))

    ;; Three standard deviations along the larger axis, in whole pixels.
    (define (radius (screen View) (det View)) (→ View)
      (let* ((middle (* (scalar 0.5) (+ (column screen 0) (column screen 2))))
             (larger (+ middle (sqrt (maximum (- (* middle middle) det) (scalar 0.1))))))
        (ceiling (* (scalar 3.0) (sqrt larger)))))

    ;; ---- Color ----

    ;; Each gaussian's harmonics in the direction from the eye, -R^T t,
    ;; offset by 0.5 and kept from going below 0: each degree's basis, a
    ;; row, times its coefficients, as a matrix product.
    (define (shaded (cloud Cloud) (camera View)) (→ View)
      (let* ((rotation (reshape (narrow camera 0 0 9) (list 3 3)))
             (eye (negate (matmul (reshape (narrow camera 0 9 3) (list 1 3)) rotation)))
             (d (normalized-rows (- (● cloud means) eye)))
             (basis (harmonic-basis (column d 0) (column d 1) (column d 2)))
             (count (list-ref (shape-of d) 0))
             (degree (lambda (k coefficients)
                       (* (narrow (● cloud degrees) 0 (- k 1) 1)
                          (matmul (unsqueeze (narrow basis 1 (* k k) (+ (* 2 k) 1)) 1)
                                  coefficients))))
             (shade (+ (* (scalar 0.28209479177387814) (● cloud dc))
                       (+ (degree 1 (● cloud degree1))
                          (+ (degree 2 (● cloud degree2)) (degree 3 (● cloud degree3)))))))
        (maximum (+ (reshape shade (list count 3)) (scalar 0.5)) (scalar 0.0))))

    ;; The real spherical harmonics of degrees 1 to 3, with the reference's
    ;; constants and signs, at their places among all 16: degree k's are
    ;; columns k^2 to k^2 + 2k. Column 0, degree 0's constant, is unused.
    (define (harmonic-basis (x View) (y View) (z View)) (→ View)
      (let* ((k (lambda (c) (scalar c)))
             (xx (* x x))
             (yy (* y y))
             (zz (* z z)))
        (concat (list (zeros-like x)
                      (* (k -0.4886025119029199) y)
                      (* (k 0.4886025119029199) z)
                      (* (k -0.4886025119029199) x)
                      (* (k 1.0925484305920792) (* x y))
                      (* (k -1.0925484305920792) (* y z))
                      (* (k 0.31539156525252005) (- (* (k 2.0) zz) (+ xx yy)))
                      (* (k -1.0925484305920792) (* x z))
                      (* (k 0.5462742152960396) (- xx yy))
                      (* (k -0.5900435899266435) (* y (- (* (k 3.0) xx) yy)))
                      (* (k 2.890611442640554) (* (* x y) z))
                      (* (k -0.4570457994644658) (* y (- (* (k 4.0) zz) (+ xx yy))))
                      (* (k 0.3731763325901154) (* z (- (* (k 2.0) zz) (* (k 3.0) (+ xx yy)))))
                      (* (k -0.4570457994644658) (* x (- (* (k 4.0) zz) (+ xx yy))))
                      (* (k 1.445305721320277) (* z (- xx yy)))
                      (* (k -0.5900435899266435) (* x (- xx (* (k 3.0) yy)))))
                1)))

    ;; ---- Binning ----

    ;; The tiles of the sensor, 16 pixels a side.
    (define (tiles-x (sensor Sensor)) (→ I64) (tiles (● sensor width) 16))
    (define (tiles-y (sensor Sensor)) (→ I64) (tiles (● sensor height) 16))
    (define (tile-count (sensor Sensor)) (→ I64) (* (tiles-x sensor) (tiles-y sensor)))

    ;; The first unused tile id is the padding key. Sort enough whole bytes
    ;; to distinguish it from every tile on this sensor.
    (define (tile-key-bits (sensor Sensor)) (→ I64)
      (let ((padding (tile-count sensor)))
        (cond ((< padding 256) 8)
              ((< padding 65536) 16)
              ((< padding 16777216) 24)
              (else 32))))

    (define (constants (sensor Sensor) (count I64)) (→ String)
      (string-append "const WIDTH = " (show (● sensor width)) "u;\n"
                     "const HEIGHT = " (show (● sensor height)) "u;\n"
                     "const TILES_X = " (show (tiles-x sensor)) "u;\n"
                     "const TILES_Y = " (show (tiles-y sensor)) "u;\n"
                     "const TILE_COUNT = TILES_X * TILES_Y;\n"
                     "const COUNT = " (show count) "u;\n"
                     "const CAPACITY = " (show (● sensor capacity)) "u;\n"))

    (define (no-gradient (args (List View)) (outs (List (Option View)))) (→ (List (Option View)))
      (map (lambda (_) (None)) args))

    (define (kernel (code String) (entry String) (bindings (List I64)) (workgroups I64)) (→ Kernel)
      (new Kernel (code code) (entry entry) (bindings bindings) (workgroups workgroups)))

    (define (u32-port (name String) (count I64)) (→ Port)
      (new Port (name name) (shape (list count)) (etype (Unsigned))))

    ;; Each tile's entries, near to far: the sorted gaussian ids, and each
    ;; tile's start and end in them.
    (define (binned (p Projection) (sensor Sensor)) (→ (Pair View View))
      (let* ((count (list-ref (shape-of (● p centers)) 0))
             (code (lambda (text) (string-append (constants sensor count) splat-tiles-shader text)))
             (label (lambda (what) (string-append what " " (constants sensor count))))
             (radii (reshape (● p radii) (list count)))
             (counts (only-port (custom (new Custom
                                          (name (label "splat-count"))
                                          (kernels (list (kernel (code splat-count-shader)
                                                                 "count_tiles"
                                                                 (list 0 1 2)
                                                                 (tiles count 256))))
                                          (adjoint no-gradient))
                                        (list (● p centers) radii)
                                        (list (u32-port "counts" count)))))
             (order (● (sort-pairs (bitcast (reshape (● p depths) (list count)) (Unsigned))
                                   (exclusive-scan (ones-like counts))
                                   32)
                       second))
             (sorted-counts (gather counts order))
             (offsets (exclusive-scan sorted-counts))
             (capacity (● sensor capacity))
             (entries (custom (new Custom
                                (name (label "splat-keys"))
                                (kernels (list (kernel (code splat-keys-shader)
                                                       "emit_keys"
                                                       (list 0 1 2 3 5 6)
                                                       (tiles count 256))
                                               (kernel (code splat-keys-shader)
                                                       "pad_keys"
                                                       (list 3 4 5)
                                                       (tiles capacity 256))))
                                (adjoint no-gradient))
                              (list (● p centers) radii order offsets sorted-counts)
                              (list (u32-port "keys" capacity) (u32-port "ids" capacity))))
             (by-tile (sort-pairs (list-ref entries 0) (list-ref entries 1) (tile-key-bits sensor)))
             (ranges (only-port (custom (new Custom
                                          (name (label "splat-ranges"))
                                          (kernels (list (kernel (code splat-ranges-shader)
                                                                 "find_ranges"
                                                                 (list 0 1)
                                                                 (tiles capacity 256))))
                                          (adjoint no-gradient))
                                        (list (● by-tile first))
                                        (list (u32-port "ranges" (* 2 (tile-count sensor))))))))
        (new Pair (first (● by-tile second)) (second ranges))))

    (define (only-port (views (List View))) (→ View) (list-ref views 0))

    ;; ---- Rasterizing ----

    ;; The image, H x W x 3, of the projected gaussians, and the projection
    ;; it was drawn from, whose centers' gradient densification watches.
    (record Rendering
      ((image View)
       (projection Projection)))

    (define (render (cloud Cloud) (camera View) (sensor Sensor)) (→ Rendering)
      (let* ((p (project cloud camera sensor))
             (bins (binned p sensor)))
        (new Rendering
          (image (only-port (rasterized sensor
                                        (list (● bins first)
                                              (● bins second)
                                              (concat
                                               (list (● p centers)
                                                     (● p conics)
                                                     (● p colors)
                                                     (● p opacities))
                                               1)))))
          (projection p))))

    (define (rasterized (sensor Sensor) (args (List View))) (→ (List View))
      (custom (forward sensor (list-ref (shape-of (list-ref args 2)) 0))
              args
              (forward-ports sensor)))

    ;; Each gaussian is nine floats to the rasterizer: center x y, conic
    ;; a b c, color r g b and opacity; its gradient has the same layout.

    (define (forward-ports (sensor Sensor)) (→ (List Port))
      (let ((pixels (* (● sensor width) (● sensor height))))
        (list (new Port
                (name "image")
                (shape (list (● sensor height) (● sensor width) 3))
                (etype (Float)))
              (new Port (name "finals") (shape (list pixels)) (etype (Float)))
              (u32-port "contributed" pixels))))

    ;; The forward pass, whose adjoint runs the backward pass on the
    ;; forward's own ports, found again by building the same node.
    (define (forward (sensor Sensor) (count I64)) (→ Custom)
      (new Custom
        (name (string-append "splat-forward " (constants sensor count)))
        (kernels (list (kernel (string-append (constants sensor count) splat-forward-shader)
                               "rasterize"
                               (list 0 1 2 3 4 5)
                               (tile-count sensor))))
        (adjoint (lambda (args outs) (rasterizer-adjoint sensor count args outs)))))

    (define (rasterizer-adjoint (sensor Sensor)
                                (count I64)
                                (args (List View))
                                (outs (List (Option View))))
      (→ (List (Option View)))
      (let* ((ports (rasterized sensor args))
             (image-grad (match (list-ref outs 0)
                           ((Some g) g)
                           ((None) (zeros-like (list-ref ports 0)))))
             (grads (only-port (custom (backward sensor count)
                                       (append args
                                               (list (list-ref ports 1)
                                                     (list-ref ports 2)
                                                     image-grad))
                                       (list (new Port
                                               (name "grads")
                                               (shape (list count 9))
                                               (etype (Float))))))))
        (list (None) (None) (Some grads))))

    (define (backward (sensor Sensor) (count I64)) (→ Custom)
      (new Custom
        (name (string-append "splat-backward " (constants sensor count)))
        (kernels (list (kernel (string-append (constants sensor count) splat-backward-shader)
                               "rasterize_backward"
                               (list 0 1 2 3 4 5 6)
                               (tile-count sensor))))
        (adjoint no-gradient)))

    ;; ---- Loss ----

    ;; A gaussian blur of an H x W x C image over 11 pixels at sigma 1.5,
    ;; zeros past its edges: its own adjoint.
    (define (blur (image View)) (→ View)
      (let* ((shape (shape-of image))
             (count (product shape))
             (consts (string-append "const HEIGHT = " (show (list-ref shape 0)) "u;\n"
                                    "const WIDTH = " (show (list-ref shape 1)) "u;\n"
                                    "const CHANNELS = " (show (list-ref shape 2)) "u;\n"
                                    "var<private> WEIGHTS: array<f32, 11> = array<f32, 11>("
                                    (string-join (map f64->string blur-weights) ", ")
                                    ");\n"))
             (c (new Custom
                  (name (string-append "splat-blur " consts))
                  (kernels (list (kernel (string-append consts splat-blur-shader)
                                         "blur_rows"
                                         (list 0 1)
                                         (tiles count 256))
                                 (kernel (string-append consts splat-blur-shader)
                                         "blur_columns"
                                         (list 1 2)
                                         (tiles count 256))))
                  (adjoint (lambda (args outs)
                             (list (match (list-ref outs 1)
                                     ((Some g) (Some (blur g)))
                                     ((None) (None)))))))))
        (list-ref (custom c
                          (list image)
                          (list (new Port (name "rows") (shape shape) (etype (Float)))
                                (new Port (name "blurred") (shape shape) (etype (Float)))))
                  1)))

    (define blur-weights
      (→ (List F64))
      (let* ((raw (map (lambda (k) (exp (/ (negate (square-f (i64->f64 (- k 5)))) 4.5))) (iota 11)))
             (total (fold-left + 0.0 raw)))
        (map (lambda (w) (/ w total)) raw)))

    (define (square-f (x F64)) (→ F64) (* x x))

    ;; The structural similarity of two images at each pixel and channel,
    ;; through the blur's window, as the reference computes it.
    (define (ssim (x View) (y View)) (→ View)
      (let* ((mx (blur x))
             (my (blur y))
             (sxx (- (blur (* x x)) (* mx mx)))
             (syy (- (blur (* y y)) (* my my)))
             (sxy (- (blur (* x y)) (* mx my)))
             (c1 (scalar 0.0001))
             (c2 (scalar 0.0009))
             (two (scalar 2.0)))
        (/ (* (+ (* two (* mx my)) c1) (+ (* two sxy) c2))
           (* (+ (+ (* mx mx) (* my my)) c1) (+ (+ sxx syy) c2)))))

    ;; (1 - lambda) L1 + lambda (1 - SSIM), the reference's loss.
    (define (photometric-loss (image View) (target View) (lambda-ssim F64)) (→ View)
      (+ (* (scalar (- 1.0 lambda-ssim)) (mean (absolute (- image target))))
         (* (scalar lambda-ssim) (- (scalar 1.0) (mean (ssim image target))))))

    ;; An H x W x 3 image of floats from RGBA8 texels, a u32 each, in rows
    ;; `pitch` texels apart, as a copy from a texture lays them out.
    (define (rgba8-image (texels View) (width I64)) (→ View)
      (let ((words (narrow texels 1 0 width)))
        (stack (map (lambda (k)
                      (/ (convert (bit-and-shifted words (* 8 k)) (Float)) (scalar 255.0)))
                    (iota 3))
               2)))

    (define (bit-and-shifted (words View) (shift I64)) (→ View)
      (binary (BitAnd)
              (binary (ShiftRight) words (fill (i64->f64 shift) (Nil) (Unsigned)))
              (fill 255.0 (Nil) (Unsigned))))

    ))
