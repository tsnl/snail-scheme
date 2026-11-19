;; COLMAP's sparse reconstructions, the binary files `cameras.bin`,
;; `images.bin` and `points3D.bin` that structure from motion leaves and
;; 3D Gaussian Splatting trains from: each camera's intrinsics, each
;; image's pose and file name, and each point's position and color.
;; Every number is little-endian.
;;
;;   (read-cameras bytes)   ; (Ok (list camera ...)) or why not
;;
;; A pose maps the world into the camera, x_camera = R x_world + t, R
;; from the quaternion w x y z; the camera looks down +z with +y down its
;; image. Only the undistorted models training draws through are read:
;; SIMPLE_PINHOLE and PINHOLE.
(define-library (snail shell graphics colmap)
  (export
   ColmapCamera
   ColmapImage
   ColmapPoint
   read-cameras
   read-images
   read-points
   image-rotation
   image-center
   poses-up
   camera-sized
   camera-values)
  (import
   (snail core base))
  (begin

    ;; ---- Records ----

    ;; A camera's pixels and its pinhole: focal lengths and principal
    ;; point in pixels, pixel (x, y) centered at (x + 0.5, y + 0.5).
    (record ColmapCamera
      ((id I64)
       (width I64)
       (height I64)
       (fx F64)
       (fy F64)
       (cx F64)
       (cy F64)))

    ;; An image's pose, its rotation w x y z and translation, the camera
    ;; it was taken with, and its file's name.
    (record ColmapImage
      ((id I64)
       (rotation (List F64))
       (translation (List F64))
       (camera I64)
       (name String)))

    (record ColmapPoint
      ((position (List F64))
       (color (List F64))))

    ;; ---- Numbers ----

    (define (byte-at (bytes Bytes) (at I64)) (→ I64) (i32->i64 (u8->i32 (array-ref bytes at))))

    ;; `count` bytes from `at`, little-endian, as one integer.
    (define (integer-at (bytes Bytes) (at I64) (count I64)) (→ I64)
      (fold-left (lambda (value k) (i64-or (i64-shift-left value 8) (byte-at bytes (+ at k))))
                 0
                 (reverse (iota count))))

    (define (i32-at (bytes Bytes) (at I64)) (→ I64)
      (let ((word (integer-at bytes at 4))) (if (>= word 2147483648) (- word 4294967296) word)))

    (define (f64-at (bytes Bytes) (at I64)) (→ F64) (bits->f64 (integer-at bytes at 8)))

    (define (f64s-at (bytes Bytes) (at I64) (count I64)) (→ (List F64))
      (map (lambda (k) (f64-at bytes (+ at (* 8 k)))) (iota count)))

    (define (fits? (bytes Bytes) (at I64) (count I64))
      (→ Bool)
      (<= (+ at count) (array-length bytes)))

    ;; Records read one after another from `at`: `one` answers a record
    ;; and where the next starts, or why it cannot.
    (define (records (bytes Bytes) (file String) (one (Fn I64 → (Result (Pair T I64) String))))
      (→ (Result (List T) String))
      (∀ (T))
      (if (fits? bytes 0 8)
          (records-from one (integer-at bytes 0 8) 8 (Nil))
          (Err (string-append file ": too short for its count"))))

    (define (records-from (one (Fn I64 → (Result (Pair T I64) String)))
                          (left I64)
                          (at I64)
                          (read (List T)))
      (→ (Result (List T) String))
      (∀ (T))
      (if (= left 0)
          (Ok (reverse read))
          (match (one at)
            ((Ok pair) (records-from one (- left 1) (● pair second) (Cons (● pair first) read)))
            ((Err why) (Err why)))))

    ;; ---- Cameras ----

    ;; id, model, width and height, then the model's parameters.
    (define (read-cameras (bytes Bytes)) (→ (Result (List ColmapCamera) String))
      (records bytes "cameras.bin" (lambda (at) (camera-at bytes at))))

    (define (camera-at (bytes Bytes) (at I64)) (→ (Result (Pair ColmapCamera I64) String))
      (if (not (fits? bytes at 24))
          (Err "cameras.bin: truncated")
          (let ((model (i32-at bytes (+ at 4))))
            (match model
              (0 (pinhole bytes
                          at
                          3
                          (lambda (p)
                            (list (list-ref p 0) (list-ref p 0) (list-ref p 1) (list-ref p 2)))))
              (1 (pinhole bytes at 4 (lambda (p) p)))
              (_ (Err (string-append "cameras.bin: camera model "
                                     (show model)
                                     " is not a pinhole; undistort the images first")))))))

    ;; A pinhole's `count` parameters, as fx fy cx cy.
    (define (pinhole (bytes Bytes) (at I64) (count I64) (focal (Fn (List F64) → (List F64))))
      (→ (Result (Pair ColmapCamera I64) String))
      (if (not (fits? bytes (+ at 24) (* 8 count)))
          (Err "cameras.bin: truncated")
          (let ((p (focal (f64s-at bytes (+ at 24) count))))
            (Ok (new Pair
                  (first (new ColmapCamera
                           (id (i32-at bytes at))
                           (width (integer-at bytes (+ at 8) 8))
                           (height (integer-at bytes (+ at 16) 8))
                           (fx (list-ref p 0))
                           (fy (list-ref p 1))
                           (cx (list-ref p 2))
                           (cy (list-ref p 3))))
                  (second (+ at (+ 24 (* 8 count)))))))))

    ;; ---- Images ----

    ;; id, rotation, translation, camera id, a name ended by a 0 byte, and
    ;; the image's 2D points, 24 bytes each, which training does not use.
    (define (read-images (bytes Bytes)) (→ (Result (List ColmapImage) String))
      (records bytes "images.bin" (lambda (at) (image-at bytes at))))

    (define (image-at (bytes Bytes) (at I64)) (→ (Result (Pair ColmapImage I64) String))
      (match (if (fits? bytes at 64) (name-end bytes (+ at 64)) (None))
        ((Some end)
         (if (not (fits? bytes (+ end 1) 8))
             (Err "images.bin: truncated")
             (let ((next (+ (+ end 9) (* 24 (integer-at bytes (+ end 1) 8)))))
               (if (> next (array-length bytes))
                   (Err "images.bin: truncated")
                   (Ok (new Pair
                         (first (new ColmapImage
                                  (id (i32-at bytes at))
                                  (rotation (f64s-at bytes (+ at 4) 4))
                                  (translation (f64s-at bytes (+ at 36) 3))
                                  (camera (i32-at bytes (+ at 60)))
                                  (name (list->string (map (lambda (k)
                                                             (integer->char
                                                              (byte-at bytes (+ (+ at 64) k))))
                                                           (iota (- end (+ at 64))))))))
                         (second next)))))))
        ((None) (Err "images.bin: truncated"))))

    ;; Where the 0 byte ending a name from `at` is.
    (define (name-end (bytes Bytes) (at I64)) (→ (Option I64))
      (cond ((not (fits? bytes at 1)) (None))
            ((= (byte-at bytes at) 0) (Some at))
            (else (name-end bytes (+ at 1)))))

    ;; R's rows from a pose's quaternion w x y z, as COLMAP's qvec2rotmat.
    (define (image-rotation (image ColmapImage)) (→ (List F64))
      (let* ((q (● image rotation))
             (w (list-ref q 0))
             (x (list-ref q 1))
             (y (list-ref q 2))
             (z (list-ref q 3)))
        (list (- 1.0 (* 2.0 (+ (* y y) (* z z))))
              (* 2.0 (- (* x y) (* w z)))
              (* 2.0 (+ (* z x) (* w y)))
              (* 2.0 (+ (* x y) (* w z)))
              (- 1.0 (* 2.0 (+ (* x x) (* z z))))
              (* 2.0 (- (* y z) (* w x)))
              (* 2.0 (- (* z x) (* w y)))
              (* 2.0 (+ (* y z) (* w x)))
              (- 1.0 (* 2.0 (+ (* x x) (* y y)))))))

    ;; Where a pose's camera stands: -R^T t.
    (define (image-center (image ColmapImage)) (→ (List F64))
      (let ((r (image-rotation image)) (t (● image translation)))
        (map (lambda (j)
               (negate (fold-left +
                                  0.0
                                  (map (lambda (i) (* (list-ref r (+ (* 3 i) j)) (list-ref t i)))
                                       (iota 3)))))
             (iota 3))))

    ;; Which way is up among poses, a reconstruction's frame having no up
    ;; of its own: the mean of what the cameras call up, each the opposite
    ;; of its rotation's second row, since a camera's y runs down; and the
    ;; frame's own -y for no poses, or for poses that agree on none.
    (define (poses-up (images (List ColmapImage))) (→ (List F64))
      (let* ((downs (map (lambda (image) (take (list-tail (image-rotation image) 3) 3)) images))
             (sum (map (lambda (axis)
                         (fold-left - 0.0 (map (lambda (down) (list-ref down axis)) downs)))
                       (iota 3)))
             (norm (sqrt (fold-left + 0.0 (map (lambda (x) (* x x)) sum)))))
        (if (< norm 1e-9) (list 0.0 -1.0 0.0) (map (lambda (x) (/ x norm)) sum))))

    ;; The camera as it took photographs `width` by `height`: a dataset
    ;; often keeps its photographs smaller than the camera took them, and
    ;; the pinhole is scaled as their width is.
    (define (camera-sized (camera ColmapCamera) (width I64) (height I64)) (→ ColmapCamera)
      (let ((scale (/ (i64->f64 width) (i64->f64 (● camera width)))))
        (new ColmapCamera
          (id (● camera id))
          (width width)
          (height height)
          (fx (* scale (● camera fx)))
          (fy (* scale (● camera fy)))
          (cx (* scale (● camera cx)))
          (cy (* scale (● camera cy))))))

    ;; The 16 floats of splat training's camera param: R's rows, t, then
    ;; fx, fy, cx and cy.
    (define (camera-values (camera ColmapCamera) (image ColmapImage)) (→ (List F64))
      (append (image-rotation image)
              (append (● image translation)
                      (list (● camera fx) (● camera fy) (● camera cx) (● camera cy)))))

    ;; ---- Points ----

    ;; id, position, color, error, then a track of 8 bytes an image that
    ;; sees the point, which training does not use.
    (define (read-points (bytes Bytes)) (→ (Result (List ColmapPoint) String))
      (records bytes "points3D.bin" (lambda (at) (point-at bytes at))))

    (define (point-at (bytes Bytes) (at I64)) (→ (Result (Pair ColmapPoint I64) String))
      (if (not (fits? bytes at 51))
          (Err "points3D.bin: truncated")
          (let ((next (+ (+ at 51) (* 8 (integer-at bytes (+ at 43) 8)))))
            (if (> next (array-length bytes))
                (Err "points3D.bin: truncated")
                (Ok (new Pair
                      (first (new ColmapPoint
                               (position (f64s-at bytes (+ at 8) 3))
                               (color (map (lambda (k)
                                             (/ (i64->f64 (byte-at bytes (+ at (+ 32 k)))) 255.0))
                                           (iota 3)))))
                      (second next)))))))

    ))
