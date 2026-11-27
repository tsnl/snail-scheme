;; Read a 3DGS PLY file, round-trip a trained cloud, and check which
;; malformed files the reader rejects.
(import
 (snail core base)
 (snail core io)
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

;; The second gaussian's record, read back: position, transform,
;; quaternion, scale and opacity, the last two as their f16s hold them;
;; then its first five colors.

(define (f32-text (x F32)) (→ String) (f64->string (f32->f64 x)))

(define (show-cloud (out OutputPort) (cloud Cloud)) (→ Unit)
  (let ((g (cloud-gaussian cloud 1)) (text (lambda (xs) (string-join (map f32-text xs) " "))))
    (write-line out (string-append "count: " (show (● cloud count))))
    (write-line out
                (string-append "position: "
                               (text (list (● g position x) (● g position y) (● g position z)))))
    (write-line out (string-append "center: "
                                   (string-join (map f64->string (cloud-center cloud 1)) " ")))
    (write-line out (string-append "transform: " (show (● g transform))))
    (write-line out
                (string-append "rotation: "
                               (text (list (● g rotation x)
                                           (● g rotation y)
                                           (● g rotation z)
                                           (● g rotation w)))))
    (write-line out
                (string-append "scale: "
                               (text (list (● g scale-opacity x)
                                           (● g scale-opacity y)
                                           (● g scale-opacity z)))))
    (write-line out (string-append "opacity: " (text (list (● g scale-opacity w))))))
  (write-line out (string-append "colors: " (colors cloud 0 5)))
  (write-line out (string-append "beyond degree 1: " (colors cloud 4 1))))

;; The second gaussian's colors `from` and on, `count` of them, each its
;; red, green and blue, read back from their halves.
(define (colors (cloud Cloud) (from I64) (count I64)) (→ String)
  (string-join (concatenate (map (lambda (k)
                                   (map (lambda (c)
                                          (f64->string (cloud-coefficient cloud 1 (+ from k) c)))
                                        (iota 3)))
                                 (iota count)))
               " "))

(define (refusal (lines (List String))) (→ String)
  (match (read-ply (array-append (header-bytes lines) (float-bytes (list 0.0))) 0)
    ((Ok _) "read")
    ((Err message) message)))

;; ---- Writing ----

;; A trained cloud of three rows, the second not a gaussian: row i's
;; floats count up from 10 i in each array, but for its quaternion, w
;; alone, and its opacity's logit, 0.
(define (trained) (→ Trained)
  (let ((counting (lambda (width)
                    (float-bytes (concatenate (map (lambda (i)
                                                     (map (lambda (k)
                                                            (f64->f32 (i64->f64 (+ (* 10 i) k))))
                                                          (iota width)))
                                                   (iota 3)))))))
    (new Trained
      (live (float-bytes (list 1.0 0.0 1.0)))
      (centers (counting 3))
      (scales (float-bytes (list 0.0 0.0 0.0 0.0 0.0 0.0 0.0 -1.0 1.0)))
      (rotations (float-bytes (list 0.0 0.0 0.0 2.0 0.0 0.0 0.0 2.0 0.0 0.0 0.0 2.0)))
      (opacities (float-bytes (list 0.0 0.0 0.0)))
      (dc (counting 3))
      (degree1 (counting 9))
      (degree2 (counting 15))
      (degree3 (counting 21)))))

;; The file written, by its size and its header's first lines, and read
;; back: the second of its two gaussians is the third row.
(define (written (out OutputPort)) (→ Unit)
  (let ((file (write-ply (trained))))
    (write-line out (string-append "written: " (show (array-length file)) " bytes"))
    (match (read-ply file 3)
      ((Ok cloud)
       (show-cloud out cloud)
       (write-line out (string-append "degree 3, red: "
                                      (string-join (map (lambda (k)
                                                          (f64->string
                                                           (cloud-coefficient cloud 1 (+ 9 k) 0)))
                                                        (iota 7))
                                                   " "))))
      ((Err message) (write-line out message)))))

(define (main (out OutputPort)) (→ Unit)
  (match (read-ply file 3)
    ((Ok cloud) (show-cloud out cloud))
    ((Err message) (write-line out message)))
  (written out)
  (write-line out (refusal (list "ply" "format ascii 1.0" "element vertex 1" "property float x")))
  (write-line out
              (refusal (list "ply"
                             "format binary_little_endian 1.0"
                             "element vertex 1"
                             "property uchar x")))
  (write-line out
              (refusal (list "ply"
                             "format binary_little_endian 1.0"
                             "element vertex 1"
                             "property float x")))
  (unit))
