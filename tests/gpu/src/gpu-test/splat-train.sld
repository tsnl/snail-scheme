;; The differentiable splat renderer on the device, at 64x48 pixels: one
;; gaussian's pixel against the paper's blend computed by hand; the
;; gradient of the full loss, L1 and D-SSIM, with respect to each of three
;; wide gaussians' params against central differences of the loss on the
;; device; fused SSIM's gradient against central differences of its mean;
;; and Adam pulling a perturbed cloud toward a rendered one.
(define-library (gpu-test splat-train)
  (export
   splat-forward-check
   shared-fill
   splat-tile-ranges
   splat-gradient-check
   splat-ssim-check
   splat-fit-check)
  (import
   (snail core base)
   (snail core table)
   (only (snail shell task) tasks)
   (only (snail shell gpu) gpu)
   (only (snail shell math) exp log sin)
   (rename (snail shell tensor)
           (exp tensor-exp)
           (log tensor-log)
           (sin tensor-sin))
   (only (snail shell tensor eval) bytes->values values->bytes)
   (snail shell tensor grad)
   (snail shell tensor lower)
   (snail shell tensor adam)
   (snail shell graphics splat-train))
  (begin

    ;; ---- Scenes ----

    (define sensor (→ Sensor) (new Sensor (width 64) (height 48) (capacity 4096)))

    ;; Looking down +z from the origin, 50 pixels a unit at depth 1.
    (define camera-values
      (→ (Array F64))
      (list->array (list 1.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 50.0 50.0 32.0 24.0)))

    ;; Each param's values, by name, for gaussians given as rows of
    ;; x y z, log scale, opacity logit and degree-0 color.
    (record Splat
      ((x F64)
       (y F64)
       (z F64)
       (scale F64)
       (logit F64)
       (red F64)))

    (define (cloud-values (splats (List Splat))) (→ (List (Pair String (Array F64))))
      (let ((each (lambda (f) (list->array (concatenate (map f splats))))))
        (list (new Pair (first "means") (second (each (lambda (s) (list (● s x) (● s y) (● s z))))))
              (new Pair
                (first "scales")
                (second (each (lambda (s) (list (● s scale) (* 1.2 (● s scale)) (● s scale))))))
              (new Pair
                (first "rotations")
                (second (each (lambda (s) (list 0.1 (* 0.5 (● s x)) 0.05 1.0)))))
              (new Pair (first "opacities") (second (each (lambda (s) (list (● s logit))))))
              (new Pair
                (first "dc")
                (second (each (lambda (s) (list (● s red) 0.2 (- 0.0 (● s red)))))))
              (harmonics "degree1" each 3 0.0)
              (harmonics "degree2" each 5 9.0)
              (harmonics "degree3" each 7 24.0))))

    ;; Small coefficients for a degree's `count` harmonics, varying by
    ;; gaussian and coefficient.
    (define (harmonics (name String)
                       (each (Fn (Fn Splat → (List F64)) → (Array F64)))
                       (count I64)
                       (from F64))
      (→ (Pair String (Array F64)))
      (new Pair
        (first name)
        (second (each (lambda (s)
                        (map (lambda (k) (* 0.05 (sin (+ (+ k from) (● s x)))))
                             (iota-f (* 3 count))))))))

    (define (iota-f (count I64)) (→ (List F64)) (map i64->f64 (iota count)))

    (define three
      (→ (List Splat))
      (list (new Splat (x -0.4) (y -0.1) (z 4.0) (scale -1.6) (logit 0.5) (red 1.0))
            (new Splat (x 0.3) (y 0.2) (z 4.5) (scale -1.4) (logit 0.0) (red -0.5))
            (new Splat (x 0.0) (y 0.0) (z 5.0) (scale -1.2) (logit -0.3) (red 0.3))))

    ;; Gaussians 16 to 21 pixels across, so wide that where their alpha
    ;; falls to 1/255, which the rasterizer skips, is off the image: a
    ;; pixel crossing that step would move the loss by more than any
    ;; small nudge's gradient.
    (define wide
      (→ (List Splat))
      (map (lambda (s) (Splat-scale-set s (+ (● s scale) 2.1))) three))

    ;; The cloud's rows, their live mask, every degree shading, and the camera.
    (define (written (program Program) (values (List (Pair String (Array F64)))) (live (List F64)))
      (→ Unit) (! gpu)
      (for-each
       (lambda (pair) (write-param program (● pair first) (values->bytes (● pair second) (Float))))
       values)
      (write-param program "live" (values->bytes (list->array live) (Float)))
      (write-param program "degrees" (values->bytes (list->array (list 1.0 1.0 1.0)) (Float)))
      (write-param program "camera" (values->bytes camera-values (Float))))

    (define (scalar-sink (program Program)) (→ F64) (! gpu tasks)
      (array-ref (bytes->values (read-sink program 0) (Float)) 0))

    ;; ---- Forward ----

    ;; One gaussian at depth 4 with scale 0.2, 2.5 pixels on the screen,
    ;; opacity 1/2, color 0.5 + C0 (1, 0, -1), seen from pixel (31, 23),
    ;; half a pixel from its center on each axis, rendered for training
    ;; and for viewing.

    (define (splat-forward-check) (→ String) (! gpu tasks)
      (let* ((variance (+ 6.25 0.3))
             (alpha (* 0.5 (exp (* -0.5 (/ 0.5 variance)))))
             (expected
              (map (lambda (c) (* alpha (+ 0.5 (* 0.28209479177387814 c)))) (list 1.0 0.0 -1.0)))
             (training (forward-pixel (Training)))
             (viewing (forward-pixel (Viewing)))
             (agrees? (lambda (got)
                        (every? (lambda (pair) (< (abs (- (● pair first) (● pair second))) 0.001))
                                (zip got expected)))))
        (if (and (agrees? training) (agrees? viewing))
            "blends as the paper does, for training and for viewing"
            (string-join (map f64->string (append training viewing)) " "))))

    (define (forward-pixel (purpose Purpose)) (→ (List F64)) (! gpu tasks)
      (let* ((cloud (splat-params 1))
             (image (● (render cloud (camera-param) sensor purpose) image))
             (program (lower "forward" (list image) (Nil))))
        (written program
                 (list (new Pair (first "means") (second (list->array (list 0.0 0.0 4.0))))
                       (new Pair
                         (first "scales")
                         (second (list->array (list (log 0.2) (log 0.2) (log 0.2)))))
                       (new Pair (first "rotations") (second (list->array (list 0.0 0.0 0.0 1.0))))
                       (new Pair (first "opacities") (second (list->array (list 0.0))))
                       (new Pair (first "dc") (second (list->array (list 1.0 0.0 -1.0))))
                       (new Pair (first "degree1") (second (array-generate 9 (lambda (_) 0.0))))
                       (new Pair (first "degree2") (second (array-generate 15 (lambda (_) 0.0))))
                       (new Pair (first "degree3") (second (array-generate 21 (lambda (_) 0.0)))))
                 (list 1.0))
        (run-program program)
        (let* ((pixels (bytes->values (read-sink program 0) (Float)))
               (got (map (lambda (k) (array-ref pixels (+ (* 3 (+ (* 23 64) 31)) k))) (iota 3))))
          (release-program program)
          got)))

    ;; SSIM reads the Fill through storage buffers. Addition uses the same
    ;; Fill as a literal. At the center, whose window lies inside the image,
    ;; an image's SSIM with itself is 1, so the sum is 4. Its contrast term
    ;; divides the difference of two nearly equal sums by C2 = 9e-4, which
    ;; magnifies their rounding: lavapipe gives 3.9997.
    (define (shared-fill) (→ Bool) (! gpu tasks)
      (let* ((v (fill 3.0 (list 11 11 1) (Float)))
             (center (narrow (narrow (+ v (ssim v v)) 0 5 1) 1 5 1))
             (program (lower "shared fill" (list center) (Nil))))
        (run-program program)
        (let ((value (scalar-sink program)))
          (release-program program)
          (< (abs (- value 4.0)) 0.001))))

    ;; Four splats touch one tile each, in depth order 0, 65536, 0, 65535.
    ;; Read the rasterizer's ranges input so the large image needs no buffer.
    (define (splat-tile-ranges) (→ String) (! gpu tasks)
      (let* ((sensor (new Sensor (width 4096) (height 4112) (capacity 8)))
             (image (● (render (splat-params 4) (camera-param) sensor (Viewing)) image))
             (ranges (list-ref (● image node args) 1))
             (bounds (concat (list (narrow ranges 0 0 2) (narrow ranges 0 (* 2 65535) 4)) 0))
             (program (lower "tile ranges" (list bounds) (Nil)))
             (write (lambda (name values)
                      (write-param program name (values->bytes (list->array values) (Float))))))
        (write "camera" (list 1.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 1.0 1.0 0.0 0.0))
        (write "means" (list 8.0 8.0 1.0 16.0 8208.0 2.0 24.0 24.0 3.0 16352.0 16352.0 4.0))
        (write "scales" (map (lambda (_) -20.0) (iota 12)))
        (write "rotations" (concatenate (map (lambda (_) (list 0.0 0.0 0.0 1.0)) (iota 4))))
        (write "live" (list 1.0 1.0 1.0 1.0))
        (run-program program)
        (let ((words (bytes->values (read-sink program 0) (Unsigned))))
          (release-program program)
          (string-join (map (lambda (word) (show (f64->i64 word))) (array->list words)) " "))))

    ;; ---- Gradients ----

    ;; The loss against a gray target, and each param's gradient, then
    ;; each element of each param nudged both ways on the device.

    (define (loss-of (cloud Cloud)) (→ View)
      (photometric-loss (● (render cloud (camera-param) sensor (Training)) image)
                        (param "target" (list 48 64 3) (Float))
                        0.2))

    (define (splat-gradient-check) (→ String) (! gpu tasks)
      (let* ((cloud (splat-params 3))
             (loss (loss-of cloud))
             (grads (lower "grads" (grad loss (cloud-views cloud)) (Nil)))
             (losses (lower "losses" (list loss) (Nil)))
             (values (cloud-values wide))
             (target
              (array-generate (* 48 (* 64 3)) (lambda (i) (* 0.3 (i64->f64 (remainder i 3)))))))
        (written grads values (list 1.0 1.0 1.0))
        (written losses values (list 1.0 1.0 1.0))
        (write-param grads "target" (values->bytes target (Float)))
        (write-param losses "target" (values->bytes target (Float)))
        (run-program grads)
        (let ((report
               (string-join (map-indexed (lambda (k pair) (group-report grads losses values k pair))
                                         values)
                            ", ")))
          (release-program grads)
          (release-program losses)
          report)))

    ;; Whether a param's gradient agrees with central differences, to 5%
    ;; of the larger and 2e-5, element by element.
    (define (group-report (grads Program)
                          (losses Program)
                          (values (List (Pair String (Array F64))))
                          (k I64)
                          (pair (Pair String (Array F64))))
      (→ String)
      (! gpu tasks)
      (let* ((name (● pair first))
             (base (● pair second))
             (analytic (bytes->values (read-sink grads k) (Float)))
             (bad (find (lambda (i)
                          (let ((a (array-ref analytic i)) (d (difference losses name base i)))
                            (not (< (abs (- a d)) (+ 0.00002 (* 0.05 (max (abs a) (abs d))))))))
                        (iota (array-length base)))))
        (match bad
          ((Some i)
           (string-append name " " (show i) ": " (f64->string (array-ref analytic i)) " not "
                          (f64->string (difference losses name base i))))
          ((None) (string-append name " agree")))))

    (define (difference (losses Program) (name String) (base (Array F64)) (i I64))
      (→ F64)
      (! gpu tasks)
      (let* ((h 0.01)
             (at (lambda (delta)
                   (write-param losses name
                                (values->bytes (array-generate (array-length base)
                                                               (lambda (j)
                                                                 (if (= j i)
                                                                     (+ (array-ref base j) delta)
                                                                     (array-ref base j))))
                                               (Float)))
                   (run-program losses)
                   (scalar-sink losses)))
             (above (at h))
             (below (at (negate h))))
        (write-param losses name (values->bytes base (Float)))
        (/ (- above below) (* 2.0 h))))

    ;; ---- SSIM ----

    ;; Mean SSIM of a 20x24 image against another, against the CPU's to a
    ;; part in 10,000; and its gradient at pixels in each of its four
    ;; tiles and across their borders, against central differences, to 2%.
    (define (splat-ssim-check) (→ String) (! gpu tasks)
      (let* ((x (param "x" (list 20 24 3) (Float)))
             (loss (mean (ssim x (param "y" (list 20 24 3) (Float)))))
             (grads (lower "ssim-grads" (grad loss (list x)) (Nil)))
             (losses (lower "ssim-losses" (list loss) (Nil)))
             (xs (array-generate 1440 (lambda (i) (+ 0.5 (* 0.4 (sin (* 0.37 (i64->f64 i))))))))
             (ys (array-generate 1440 (lambda (i) (+ 0.5 (* 0.3 (sin (* 0.11 (i64->f64 i)))))))))
        (for-each (lambda (program)
                    (write-param program "x" (values->bytes xs (Float)))
                    (write-param program "y" (values->bytes ys (Float))))
                  (list grads losses))
        (run-program grads)
        (run-program losses)
        (let* ((analytic (bytes->values (read-sink grads 0) (Float)))
               (mean-ssim (scalar-sink losses))
               (agrees (lambda (i)
                         (let ((a (array-ref analytic i)) (b (difference losses "x" xs i)))
                           (< (abs (- a b)) (* 0.02 (max (abs a) (abs b)))))))
               (cpu (cpu-ssim-mean xs ys 20 24))
               (report (string-append (if (< (abs (- mean-ssim cpu)) 0.0001)
                                          "mean agrees"
                                          "mean disagrees")
                                      (if (every? agrees (list 0 100 777 1201 1439))
                                          ", x agrees"
                                          ", x disagrees"))))
          (release-program grads)
          (release-program losses)
          report)))

    ;; SSIM's mean by its definition: each moment a sum over the 11x11
    ;; window of the separable gaussian at sigma 1.5, zeros past the edges.
    (define (cpu-ssim-mean (xs (Array F64)) (ys (Array F64)) (h I64) (w I64)) (→ F64)
      (let* ((raw (map (lambda (k) (exp (/ (negate (* (i64->f64 (- k 5)) (i64->f64 (- k 5)))) 4.5)))
                       (iota 11)))
             (total (fold-left + 0.0 raw))
             (weights (list->array (map (lambda (v) (/ v total)) raw)))
             (texel (lambda (a r c ch)
                      (if (and (>= r 0) (< r h) (>= c 0) (< c w))
                          (array-ref a (+ (* 3 (+ (* r w) c)) ch))
                          0.0)))
             (moment (lambda (f r c)
                       (fold-left + 0.0 (map (lambda (k)
                                               (* (* (array-ref weights (quotient k 11))
                                                     (array-ref weights (remainder k 11)))
                                                  (f (+ r (- (quotient k 11) 5))
                                                     (+ c (- (remainder k 11) 5)))))
                                             (iota 121)))))
             (at (lambda (i)
                   (let* ((ch (remainder i 3))
                          (r (quotient (quotient i 3) w))
                          (c (remainder (quotient i 3) w))
                          (x (lambda (r c) (texel xs r c ch)))
                          (y (lambda (r c) (texel ys r c ch)))
                          (mx (moment x r c))
                          (my (moment y r c))
                          (sxx (- (moment (lambda (r c) (* (x r c) (x r c))) r c) (* mx mx)))
                          (syy (- (moment (lambda (r c) (* (y r c) (y r c))) r c) (* my my)))
                          (sxy (- (moment (lambda (r c) (* (x r c) (y r c))) r c) (* mx my))))
                     (/ (* (+ (* 2.0 (* mx my)) 0.0001) (+ (* 2.0 sxy) 0.0009))
                        (* (+ (+ (* mx mx) (* my my)) 0.0001) (+ (+ sxx syy) 0.0009)))))))
        (/ (fold-left + 0.0 (map at (iota (* 3 (* h w))))) (i64->f64 (* 3 (* h w))))))

    ;; ---- Fitting ----

    ;; The three gaussians rendered as a target, then a cloud started half
    ;; a scale smaller and dimmer fitted to it by Adam for 200 steps.
    (define (splat-fit-check) (→ String) (! gpu tasks)
      (let* ((truth (splat-params 3))
             (target-program
              (lower "truth"
                     (list (● (render truth (camera-param) sensor (Viewing)) image))
                     (Nil))))
        (written target-program (cloud-values three) (list 1.0 1.0 1.0))
        (run-program target-program)
        (let ((target (read-sink target-program 0)))
          (release-program target-program)
          (fitted target))))

    (define (fitted (target Bytes)) (→ String) (! gpu tasks)
      (let* ((cloud (splat-params 4))
             (loss (loss-of cloud))
             (grads (grad loss (cloud-views cloud)))
             (rates (list 0.002 0.005 0.001 0.05 0.0025 0.000125 0.000125 0.000125))
             (program (lower "fit"
                             (list loss)
                             (adam-updates "adam"
                                           (adam 0.9 0.999 1e-15)
                                           (map (lambda (k)
                                                  (new Trained
                                                    (param
                                                     (list-ref (cloud-views cloud) k))
                                                    (grad (list-ref grads k))
                                                    (rate (scalar (list-ref rates k)))))
                                                (iota 8))))))
        (let ((initial (cloud-values (map (lambda (s)
                                            (Splat-logit-set (Splat-scale-set s (- (● s scale) 0.5))
                                                             (- (● s logit) 1.0)))
                                          three))))
          (written program (map with-spare-row initial) (list 1.0 1.0 1.0 0.0)))
        (write-param program "target" target)
        (run-program program)
        (let ((first-loss (scalar-sink program)))
          (for-each (lambda (_) (run-program program)) (iota 200))
          (let ((last-loss (scalar-sink program))
                (spare-zero (every? (lambda (name) (spare-row-zero? program name))
                                    (list "means" "rotations"))))
            (release-program program)
            (cond ((not spare-zero) "Adam changed the unused row")
                  ((< last-loss (* 0.25 first-loss)) "the loss falls by more than four times")
                  (else
                   (string-append (f64->string first-loss) " to " (f64->string last-loss))))))))

    ;; Leave a fourth gaussian uninitialized as a growing cloud does.
    (define (with-spare-row (pair (Pair String (Array F64)))) (→ (Pair String (Array F64)))
      (let ((values (● pair second)))
        (new Pair (first (● pair first))
             (second (array-append values (make-array (quotient (array-length values) 3) 0.0))))))

    (define (spare-row-zero? (program Program) (name String)) (→ Bool) (! gpu tasks)
      (let* ((values (bytes->values (read-param program name) (Float)))
             (size (array-length values)))
        (every? (lambda (x) (= x 0.0))
                (array->list (subarray values (* 3 (quotient size 4)) size)))))

    ))
