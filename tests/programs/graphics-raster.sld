;; A scene's objects, made once, and its frame through the recording
;; handler: the G-buffer pass, the sun pass and a translucent pass. A camera's inverse undoes its
;; view-projection for either lens.
(import
 (snail core base)
 (snail core io)
 (snail shell math)
 (snail shell gpu)
 (snail shell gpu record)
 (only (snail shell task) tasks)
 (snail shell graphics pod)
 (snail shell graphics mesh)
 (snail shell graphics raster)
 (snail shell graphics passes))

(define (column (m Mat4x4f) (c I64)) (→ (List F64))
  (let ((v (list-ref (list (● m x) (● m y) (● m z) (● m w)) c)))
    (list (f32->f64 (● v x)) (f32->f64 (● v y)) (f32->f64 (● v z)) (f32->f64 (● v w)))))

;; The largest entry of inverse × view-projection − identity.
(define (error-of (camera Camera3D)) (→ F64)
  (fold-left max
             0.0
             (map (lambda (index)
                    (let* ((c (quotient index 4))
                           (r (remainder index 4))
                           (sum (fold-left (lambda (sum k)
                                             (+ sum (* (list-ref (column (● camera inverse) k) r)
                                                       (list-ref
                                                        (column (● camera view-projection) c)
                                                        k))))
                                           0.0
                                           (iota 4))))
                      (abs (- sum (if (= c r) 1.0 0.0)))))
                  (iota 16))))

(define (camera (lens Lens)) (→ Camera3D)
  (camera-3d (new Vec3f (x 3.0) (y 9.0) (z 6.0)) (new Vec3f (x 1.0) (y 0.0) (z -2.0)) lens 1.5 1.0))

(define (instance (x F32)) (→ Instance)
  (let ((one (new Vec4f (x 1.0) (y 1.0) (z 1.0) (w 0.0))))
    (new Instance
      (place (new Vec4f (x x) (y 0.0) (z 0.0) (w 0.0)))
      (scale one)
      (color one)
      (from (new Vec4f (x x) (y 0.0) (z 0.0) (w 0.0)))
      (material (new Vec4f (x 0.0) (y 1.0) (z 0.0) (w 0.0))))))

;; A created object's kind, id and label, and a pass's id and encoder,
;; without their descriptors.
(define (heads (lines (List String))) (→ (List String))
  (map (lambda (line)
         (let ((words (words-of line)))
           (cond ((string=? (list-ref words 0) "create") (string-join (take words 4) " "))
                 ((string=? (list-ref words 0) "pass") (string-join (take words 3) " "))
                 (else line))))
       lines))

(define (words-of (text String)) (→ (List String))
  (match (string-index text #\space)
    ((Some at)
     (Cons (substring text 0 at) (words-of (substring text (+ at 1) (string-length text)))))
    ((None) (list text))))

(write-line (string-append "pinhole inverse within 1e-4: "
                           (show (< (error-of (camera (Pinhole 0.8))) 0.0001))))
(write-line (string-append "parallel inverse within 1e-4: "
                           (show (< (error-of (camera (Parallel 20.0))) 0.0001))))
(define (instances (mesh Mesh) (x F32)) (→ Meshes)
  (meshes (list (new Pair (first mesh) (second (instance x))))))

(define (frame) (→ Unit) (! gpu tasks)
  (request-device)
  (let* ((r (make-raster (Bgra8Unorm)))
         (g (make-gbuffer 640 480))
         (light (make-sunlight (Bgra8Unorm) g r))
         (ground (make-surface r "ground" #f solid (instances (Tile) 0.0)))
         (water (make-surface r
                              "water"
                              #t
                              (new Style (opacity 0.5) (center-x 0.0) (center-z 0.0) (radius -1.0))
                              (instances (Box) 1.0)))
         (canvas (view-of (● (current-texture) texture) 1))
         (encoder (create-command-encoder)))
    (write-raster r
                  (camera (Parallel 20.0))
                  (new Sun (direction (new Vec4f (x 0.3) (y 1.0) (z 0.5) (w 0.8))) (ambient 0.3)))
    (let ((pass (begin-gbuffer encoder g)))
      (draw-surface pass r ground)
      (end-pass pass))
    (sun-pass encoder canvas (new Color (red 0.0) (green 0.0) (blue 0.0) (alpha 1.0)) light)
    (let ((pass (begin-forward encoder canvas g)))
      (draw-surface pass r water)
      (end-pass pass))
    (submit (list (finish encoder)))))

(for-each write-line (heads (● (with-recorded-gpu frame) second)))
