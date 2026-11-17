;; Gaussian splatting without a device: a 3DGS PLY file read into a cloud,
;; with its activations, its coefficients by degree and its transform row;
;; the files `read-ply` refuses; and the dispatches a frame records, which
;; show the scan's levels inside each pass of the radix sort.
(import
 (snail core base)
 (snail core io)
 (snail shell gpu)
 (snail shell gpu record)
 (snail shell graphics pod)
 (snail shell graphics splat)
 (snail shell graphics ply))

;; ---- Files ----

(define (header-bytes (lines (List String))) (→ Bytes)
  (list->array (map (lambda (c) (i32->u8 (char->i32 c)))
                    (string->list (string-append (string-join lines "\n") "\nend_header\n")))))

(define (float-bytes (values (List F32))) (→ Bytes)
  (pack (shape) values))

;; Two gaussians of degree 1, each with a normal the reader skips: x y z,
;; nx ny nz, f_dc 0-2, f_rest 0-8 (red's three, green's, blue's), opacity,
;; scale 0-2, rot 0-3.
(define degree-one
  (→ (List String))
  (append (list "ply" "format binary_little_endian 1.0" "element vertex 2")
          (map (lambda (name) (string-append "property float " name))
               (concatenate
                (list (list "x" "y" "z" "nx" "ny" "nz" "f_dc_0" "f_dc_1" "f_dc_2")
                      (map (lambda (k) (string-append "f_rest_" (show k))) (iota 9))
                      (list "opacity"
                            "scale_0"
                            "scale_1"
                            "scale_2"
                            "rot_0"
                            "rot_1"
                            "rot_2"
                            "rot_3"))))))

(define (vertex (x F32)) (→ (List F32))
  (concatenate (list (list x 2.0 3.0 0.0 0.0 1.0 0.5 0.25 0.125)
                     (list 1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0)
                     (list 0.0 0.0 -1.0 1.0 2.0 0.0 0.0 0.0))))

(define file
  (→ Bytes)
  (array-append (header-bytes degree-one) (float-bytes (append (vertex 1.0) (vertex -1.0)))))

(define (float-at (bytes Bytes) (index I64)) (→ F32)
  (bits->f32 (fold-left (lambda (word k)
                          (i32-or (i32-shift-left word 8)
                                  (u8->i32 (array-ref bytes (+ (* 4 index) k)))))
                        0
                        (list 3 2 1 0))))

(define (floats (bytes Bytes) (from I64) (count I64)) (→ String)
  (string-join (map (lambda (index) (f64->string (f32->f64 (float-at bytes (+ from index)))))
                    (iota count))
               " "))

;; The second gaussian's record, words: position, transform, quaternion,
;; scale, opacity; then its first five colors.

(define (show-cloud (cloud Cloud)) (→ Unit) (! output-port)
  (write-line (string-append "count: " (show (● cloud count))))
  (write-line (string-append "position: " (floats (● cloud gaussians) 12 3)))
  (write-line (string-append "transform: " (show (f32->bits (float-at (● cloud gaussians) 15)))))
  (write-line (string-append "rotation: " (floats (● cloud gaussians) 16 4)))
  (write-line (string-append "scale: " (floats (● cloud gaussians) 20 3)))
  (write-line (string-append "opacity: " (floats (● cloud gaussians) 23 1)))
  (write-line (string-append "colors: " (floats (● cloud harmonics) 48 15)))
  (write-line (string-append "beyond degree 1: " (floats (● cloud harmonics) 60 3))))

(define (refusal (lines (List String))) (→ String)
  (match (read-ply (array-append (header-bytes lines) (float-bytes (list 0.0))) 0)
    ((Ok _) "read")
    ((Err message) message)))

;; ---- Dispatches ----

;; The workgroups of each dispatch a frame of 300,000 gaussians records:
;; the projection, then eight passes of the sort, each counting 1172
;; blocks, scanning their 18,752 counts in two levels and adding the upper
;; level back, and scattering.

(define (frame) (→ Unit) (! gpu)
  (let ((splats (make-splats "test" (Bgra8Unorm) 300000 2)) (encoder (create-command-encoder)))
    (write-transforms splats (list (identity-of 2.0)))
    (sort-splats encoder
                 splats
                 (splat-camera (new Vec3f (x 0.0) (y 0.0) (z 5.0))
                               (new Vec3f (x 0.0) (y 0.0) (z 0.0))
                               (new Vec3f (x 0.0) (y 1.0) (z 0.0))
                               1.0
                               640
                               480))
    (submit (list (finish encoder)))))

(define (identity-of (scale F32)) (→ Mat4x4f)
  (new Mat4x4f
    (x (new Vec4f (x scale) (y 0.0) (z 0.0) (w 0.0)))
    (y (new Vec4f (x 0.0) (y scale) (z 0.0) (w 0.0)))
    (z (new Vec4f (x 0.0) (y 0.0) (z scale) (w 0.0)))
    (w (new Vec4f (x 0.0) (y 0.0) (z 0.0) (w 1.0)))))

(define (dispatched (line String)) (→ Bool)
  (and (> (string-length line) 19) (string=? (substring line 0 19) "dispatch-workgroups")))

(define (workgroups (line String)) (→ String)
  (match (string-index (substring line 20 (string-length line)) #\space)
    ((Some at) (substring line (+ 21 at) (- (string-length line) 4)))
    ((None) line)))

(match (read-ply file 3)
  ((Ok cloud) (show-cloud cloud))
  ((Err message) (write-line message)))
(write-line (refusal (list "ply" "format ascii 1.0" "element vertex 1" "property float x")))
(write-line
 (refusal (list "ply" "format binary_little_endian 1.0" "element vertex 1" "property uchar x")))
(write-line
 (refusal (list "ply" "format binary_little_endian 1.0" "element vertex 1" "property float x")))
(write-line
 (string-join (map workgroups (filter dispatched (● (with-recorded-gpu frame) second))) " "))
