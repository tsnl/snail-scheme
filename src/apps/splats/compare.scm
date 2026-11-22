;; The splats viewer's two renderers, compared at the views a scene was
;; photographed from: the quads of (snail shell graphics splat), and the
;; renderer training descends through, rendered for viewing by
;; (snail shell graphics splat-view). Each frame's compute pass and render
;; pass are timed on the device, and each view's two images are compared
;; by PSNR. On Node, whose device times are not rounded:
;;
;;   ./snail-scheme run --target node src/apps/splats/compare.scm \
;;     cloud=bicycle.ply scene=datasets/bicycle/ views=8 width=1237
;;
;; `scene` is a COLMAP dataset's folder, ending in a slash, whose sparse/0
;; holds its cameras and images; the cloud stands in its frame. Each view
;; is drawn `width` pixels wide at its photograph's aspect, with the
;; principal point at the center, as the quads take it; both renderers
;; are first drawn once, untimed, as their pipelines are made then.
;; `photos=images_4` names the scene's photographs at the target's size,
;; and each renderer's image is compared with its photograph too;
;; `profile=1` times each of the training renderer's steps alone.
(import
 (snail core base)
 (only (snail core io) Host Arguments Fs OutputPort command-line read-bytes write-line)
 (only (snail shell math) log)
 (snail shell gpu)
 (snail shell graphics pod)
 (snail shell graphics colmap)
 (only (snail shell graphics ply) read-ply)
 (snail shell graphics splat)
 (snail shell graphics splat-view)
 (only (snail shell tensor lower) profile-program))

;; ---- Settings ----

;; The value of `name=value` among the arguments.
(define (setting (arguments Arguments) (name String)) (→ (Option String))
  (let ((prefix (string-append name "=")))
    (match (find (lambda (word)
                   (and (>= (string-length word) (string-length prefix))
                        (string=? (substring word 0 (string-length prefix)) prefix)))
                 (list-tail (command-line arguments) 1))
      ((Some word) (Some (substring word (string-length prefix) (string-length word))))
      ((None) (None)))))

(define (required (arguments Arguments) (name String)) (→ String)
  (match (setting arguments name)
    ((Some value) value)
    ((None) (panic (string-append "compare: name the " name ", as " name "=PATH")))))

(define (number (arguments Arguments) (name String) (otherwise I64)) (→ I64)
  (match (setting arguments name)
    ((Some value)
     (match (string->i64 value)
       ((Some n) n)
       ((None) (panic (string-append "compare: " name " is not a whole number")))))
    ((None) otherwise)))

(define (told (what String) (result (Result T String))) (→ T) (∀ (T))
  (match result
    ((Ok value) value)
    ((Err why) (panic (string-append "compare: " what ": " why)))))

;; ---- Views ----

;; `count` of the images, evenly through them.
(define (evenly (images (List ColmapImage)) (count I64)) (→ (List ColmapImage))
  (let ((step (max 1 (quotient (length images) count))))
    (map (lambda (k) (list-ref images (* k step)))
         (iota (min count (quotient (+ (length images) (- step 1)) step))))))

(define (camera-of (cameras (List ColmapCamera)) (image ColmapImage)) (→ ColmapCamera)
  (match (find (lambda (camera) (= (● camera id) (● image camera))) cameras)
    ((Some camera) camera)
    ((None) (panic (string-append "compare: no camera for " (● image name))))))

;; The quad path's camera at a photograph's pose. COLMAP's rotation rows
;; are right, down and forward; the view's are right, up and backward, so
;; its second and third rows and translations are COLMAP's negated.
(define (pose-camera (image ColmapImage) (camera ColmapCamera)) (→ SplatCamera)
  (let* ((r (image-rotation image))
         (t (● image translation))
         (sign (lambda (i) (if (= i 0) 1.0 -1.0)))
         (column (lambda (j)
                   (new Vec4f
                     (x (f64->f32 (list-ref r j)))
                     (y (f64->f32 (* -1.0 (list-ref r (+ 3 j)))))
                     (z (f64->f32 (* -1.0 (list-ref r (+ 6 j)))))
                     (w 0.0))))
         (eye (image-center image)))
    (new SplatCamera
      (view (new Mat4x4f
              (x (column 0))
              (y (column 1))
              (z (column 2))
              (w (new Vec4f
                   (x (f64->f32 (list-ref t 0)))
                   (y (f64->f32 (* (sign 1) (list-ref t 1))))
                   (z (f64->f32 (* (sign 2) (list-ref t 2))))
                   (w 1.0)))))
      (eye (new Vec4f
             (x (f64->f32 (list-ref eye 0)))
             (y (f64->f32 (list-ref eye 1)))
             (z (f64->f32 (list-ref eye 2)))
             (w 1.0)))
      (focal (new Vec2f (x (f64->f32 (● camera fx))) (y (f64->f32 (● camera fy)))))
      (viewport (new Vec2f (x (i64->f32 (● camera width))) (y (i64->f32 (● camera height))))))))

;; ---- Frames ----

;; A frame's two passes' seconds on the device, and its image read back,
;; rows `pitch` bytes apart.
(record Drawn
  ((compute F64)
   (draw F64)
   (pixels Bytes)))

;; The target, and the buffer its image is read back through.
(record Target
  ((texture GpuTexture)
   (readback GpuBuffer)
   (width I64)
   (height I64)
   (pitch I64)))

(define (target-of (gpu Gpu) (width I64) (height I64)) (→ Target)
  (let ((pitch (* 256 (quotient (+ (* 4 width) 255) 256))))
    (new Target
      (texture (create-texture gpu (new TextureDescriptor
                                     (label "compare")
                                     (width (i64->i32 width))
                                     (height (i64->i32 height))
                                     (layers 1)
                                     (mips 1)
                                     (format (Rgba8Unorm))
                                     (usage (list (RenderAttachment) (TextureCopySrc))))))
      (readback (create-buffer gpu (new BufferDescriptor
                                     (label "compare/readback")
                                     (size (i64->i32 (* pitch height)))
                                     (usage (list (MapRead) (CopyDst))))))
      (width width)
      (height height)
      (pitch pitch))))

;; The splats drawn as quads, and by the training renderer.

(define (quads (gpu Gpu) (splats Splats) (camera SplatCamera) (target Target)) (→ Drawn)
  (let* ((queries (create-query-set gpu (new QuerySetDescriptor (label "quads") (count 4))))
         (encoder (create-command-encoder gpu))
         (compute (begin-timed-compute-pass gpu encoder (writes queries 0))))
    (sort-splats gpu compute splats camera)
    (end-compute-pass gpu compute)
    (let ((pass (begin-timed-render-pass gpu encoder (cleared gpu target) (writes queries 2))))
      (draw-splats gpu pass splats)
      (end-pass gpu pass))
    (timed-frame gpu encoder queries target)))

(define (tiles (gpu Gpu) (view SplatView) (camera SplatCamera) (target Target)) (→ Drawn)
  (let* ((queries (create-query-set gpu (new QuerySetDescriptor (label "tiles") (count 4))))
         (encoder (create-command-encoder gpu))
         (compute (begin-timed-compute-pass gpu encoder (writes queries 0))))
    (write-view-camera gpu view camera)
    (encode-splat-view gpu compute view)
    (end-compute-pass gpu compute)
    (let ((pass (begin-timed-render-pass gpu encoder (cleared gpu target) (writes queries 2))))
      (present-splat-view gpu pass view)
      (end-pass gpu pass))
    (timed-frame gpu encoder queries target)))

(define (writes (queries GpuQuerySet) (k I32)) (→ TimestampWrites)
  (new TimestampWrites (query-set queries) (beginning k) (end (+ k 1))))

(define (cleared (gpu Gpu) (target Target)) (→ RenderPassDescriptor)
  (new RenderPassDescriptor
    (colors (list (Some (new ColorAttachment
                          (view (view-of gpu (● target texture) 1))
                          (load (Clear (new Color (red 0.0) (green 0.0) (blue 0.0) (alpha 1.0))))
                          (store #t)))))
    (depth (None))))

;; The frame's image copied out, the encoder submitted, and the times and
;; the image read.
(define (timed-frame (gpu Gpu) (encoder GpuCommandEncoder) (queries GpuQuerySet) (target Target))
  (→ Drawn)
  (copy-texture-to-buffer gpu encoder
                          (whole-texture (● target texture))
                          (● target readback)
                          0
                          (i64->i32 (● target pitch))
                          (i64->i32 (● target width))
                          (i64->i32 (● target height)))
  (let ((times (submit-timed gpu encoder queries 4)))
    (destroy gpu (QuerySetObject queries))
    (new Drawn
      (compute (elapsed-seconds times 0 1))
      (draw (elapsed-seconds times 2 3))
      (pixels (read-buffer gpu (● target readback)
                           0
                           (i64->i32 (* (● target pitch) (● target height))))))))

;; ---- Agreement ----

;; The PSNR of one image against the other over red, green and blue.
(define (psnr (a Bytes) (b Bytes) (target Target)) (→ F64)
  (let* ((width (● target width))
         (height (● target height))
         (squared (let loop ((y 0) (x 0) (total 0.0))
                    (cond ((= y height) total)
                          ((= x width) (loop (+ y 1) 0 total))
                          (else (loop y
                                      (+ x 1)
                                      (+ total
                                         (pixel-error a b (+ (* y (● target pitch)) (* 4 x))))))))))
    (* 10.0 (/ (log (/ (* 255.0 (* 255.0 (i64->f64 (* 3 (* width height))))) (max squared 1e-9)))
               (log 10.0)))))

(define (pixel-error (a Bytes) (b Bytes) (at I64)) (→ F64)
  (fold-left (lambda (total k)
               (let ((d (i32->f64
                         (- (u8->i32 (array-ref a (+ at k))) (u8->i32 (array-ref b (+ at k)))))))
                 (+ total (* d d))))
             0.0
             (iota 3)))

;; ---- Comparing ----

;; A view: its photograph's name, the quad path's camera at its pose, and
;; the photograph's pixels, rows as far apart as the target's, when the
;; scene's folder of photographs at the target's size is named.
(record Pose
  ((name String)
   (camera SplatCamera)
   (photo (Option Bytes))))

;; A photograph decoded and read back as the target's image is.
(define (photograph (fs Fs) (gpu Gpu) (path String) (target Target)) (→ Bytes)
  (match (decode-image gpu (read-bytes fs path))
    ((Some image)
     (unless (and (= (i32->i64 (● image width)) (● target width))
                  (= (i32->i64 (● image height)) (● target height)))
       (panic (string-append "compare: " path " is not " (show (● target width)) "x"
                             (show (● target height)))))
     (let ((encoder (create-command-encoder gpu)))
       (copy-texture-to-buffer gpu encoder
                               (whole-texture (● image texture))
                               (● target readback)
                               0
                               (i64->i32 (● target pitch))
                               (● image width)
                               (● image height))
       (submit gpu (list (finish gpu encoder)))
       (destroy gpu (TextureObject (● image texture)))
       (read-buffer gpu (● target readback) 0 (i64->i32 (* (● target pitch) (● target height))))))
    ((None) (panic (string-append "compare: " path " is no image")))))

(define (milliseconds (seconds F64)) (→ String)
  (f64->string (/ (round (* seconds 1000000.0)) 1000.0)))

(define (decibels (value F64)) (→ String) (f64->string (/ (round (* value 100.0)) 100.0)))

(define (median (values (List F64))) (→ F64)
  (list-ref (list-sort < values) (quotient (length values) 2)))

(define (mean (values (List F64))) (→ F64)
  (/ (fold-left + 0.0 values) (i64->f64 (length values))))

;; What one view gave: each renderer's frame, the PSNR between their
;; images, and each one's against the photograph.
(record Compared
  ((quads Drawn)
   (tiles Drawn)
   (between F64)
   (photographed (Option (Pair F64 F64)))))

;; Each view drawn both ways, after drawing both once, and the medians
;; and means; with `profile`, the training renderer's twelve slowest
;; steps.
(define (compare (out OutputPort) (gpu Gpu) (splats Splats)
                 (view SplatView)
                 (poses (List Pose))
                 (target Target)
                 (profile Bool))
  (→ Unit)
  (quads gpu splats (● (list-ref poses 0) camera) target)
  (tiles gpu view (● (list-ref poses 0) camera) target)
  (when profile (profiled out gpu view))
  (let* ((rows (map (lambda (pose) (compared out gpu splats view pose target)) poses))
         (ms (lambda (f) (milliseconds (median (map f rows))))))
    (write-line out (string-append "median: quads "
                                   (ms (lambda (r) (● r quads compute)))
                                   " + "
                                   (ms (lambda (r) (● r quads draw)))
                                   " ms, tiles "
                                   (ms (lambda (r) (● r tiles compute)))
                                   " + "
                                   (ms (lambda (r) (● r tiles draw)))
                                   " ms; mean PSNR between "
                                   (decibels (mean (map (lambda (r) (● r between)) rows)))
                                   (photographed-means rows)))))

(define (photographed-means (rows (List Compared))) (→ String)
  (let ((against (concatenate (map (lambda (r)
                                     (match (● r photographed)
                                       ((Some pair) (list pair))
                                       ((None) (Nil))))
                                   rows))))
    (if (null? against)
        ""
        (string-append ", against the photographs: quads "
                       (decibels (mean (map (lambda (pair) (● pair first)) against)))
                       ", tiles "
                       (decibels (mean (map (lambda (pair) (● pair second)) against)))))))

;; One view drawn both ways, and its line written: each renderer's
;; compute and render passes in milliseconds, the PSNRs, and the tile
;; entries binning asked for.
(define (compared (out OutputPort)
                  (gpu Gpu)
                  (splats Splats)
                  (view SplatView)
                  (pose Pose)
                  (target Target))
  (→ Compared)
  (let* ((q (quads gpu splats (● pose camera) target))
         (t (tiles gpu view (● pose camera) target))
         (row (new Compared
                (quads q)
                (tiles t)
                (between (psnr (● q pixels) (● t pixels) target))
                (photographed (match (● pose photo)
                                ((Some photo)
                                 (Some (new Pair
                                         (first (psnr (● q pixels) photo target))
                                         (second (psnr (● t pixels) photo target)))))
                                ((None) (None)))))))
    (write-line out (string-append (● pose name)
                                   ": quads " (milliseconds (● q compute))
                                   " + " (milliseconds (● q draw))
                                   " ms, tiles " (milliseconds (● t compute))
                                   " + " (milliseconds (● t draw))
                                   " ms; PSNR between " (decibels (● row between))
                                   (photographed-means (list row))
                                   "; entries " (show (view-entries gpu view))))
    row))

;; The training renderer's steps timed one pass each, as `profile-program`
;; does: their count and total, and the twelve slowest.
(define (profiled (out OutputPort) (gpu Gpu) (view SplatView)) (→ Unit)
  (let ((times (list-sort (lambda (a b) (> (● a second) (● b second)))
                          (profile-program gpu (● view program)))))
    (write-line out (string-append "tiles profiled: "
                                   (show (length times))
                                   " steps, "
                                   (milliseconds
                                    (fold-left + 0.0 (map (lambda (t) (● t second)) times)))
                                   " ms"))
    (for-each (lambda (t)
                (write-line out
                            (string-append "  "
                                           (milliseconds (● t second))
                                           " ms "
                                           (first-line (● t first)))))
              (take times (min 12 (length times))))))

(define (first-line (text String)) (→ String)
  (match (string-index text #\newline)
    ((Some at) (substring text 0 at))
    ((None) text)))

;; The views, `views` of them evenly through the scene's images, each with
;; its photograph when `photos` names the folder of them at the target's
;; size, as images_4.
(define (poses-of (arguments Arguments) (fs Fs) (gpu Gpu) (scene String) (target Target))
  (→ (List Pose))
  (let* ((sparse (string-append scene "sparse/0/"))
         (cameras
          (told "cameras" (read-cameras (read-bytes fs (string-append sparse "cameras.bin")))))
         (images
          (evenly (told "images" (read-images (read-bytes fs (string-append sparse "images.bin"))))
                  (number arguments "views" 8))))
    (map (lambda (image)
           (new Pose
             (name (● image name))
             (camera (pose-camera image
                                  (camera-sized (camera-of cameras image)
                                                (● target width)
                                                (● target height))))
             (photo (match (setting arguments "photos")
                      ((Some folder)
                       (Some
                        (photograph fs gpu (string-append scene folder "/" (● image name)) target)))
                      ((None) (None))))))
         images)))

;; The target's height at `width`, rounded, as a dataset's smaller
;; photographs are: the first camera's aspect.
(define (height-at (fs Fs) (scene String) (width I64)) (→ I64)
  (let ((camera (list-ref (told "cameras"
                                (read-cameras
                                 (read-bytes fs (string-append scene "sparse/0/cameras.bin"))))
                          0)))
    (quotient (+ (* width (● camera height)) (quotient (● camera width) 2)) (● camera width))))

(define (main (arguments Arguments) (fs Fs) (out OutputPort) (host Host)) (→ Unit)
  (let ((gpu (host-gpu host)))
    (request-device gpu)
    (let* ((cloud (told "cloud" (read-ply (read-bytes fs (required arguments "cloud")) 0)))
           (scene (required arguments "scene"))
           (width (number arguments "width" 1237))
           (target (target-of gpu width (height-at fs scene width)))
           (poses (poses-of arguments fs gpu scene target))
           (splats (make-splats gpu "compare" (Rgba8Unorm) (● cloud count) 1)))
      (write-cloud gpu splats 0 cloud)
      (write-line out (string-append (show (● cloud count))
                                     " gaussians, "
                                     (show (● target width))
                                     "x"
                                     (show (● target height))))
      (let ((view (make-splat-view gpu splats
                                   (Rgba8Unorm)
                                   (● target width)
                                   (● target height)
                                   (* 4 (● cloud count)))))
        (compare out
                 gpu
                 splats
                 view
                 poses
                 target
                 (match (setting arguments "profile") ((Some _) #t) ((None) #f)))
        (release-splat-view gpu view)
        (release-splats gpu splats)))))
