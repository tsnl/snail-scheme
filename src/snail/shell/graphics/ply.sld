;; The PLY files 3D Gaussian Splatting trains: read into a `Cloud` for
;; (snail shell graphics splat), and written from a cloud as training
;; keeps it. Such a file is a text header naming one
;; `vertex` element's float properties, then each vertex's floats,
;; little-endian:
;;
;;   ply
;;   format binary_little_endian 1.0
;;   element vertex 1000
;;   property float x            ; and y, z: the center
;;   property float f_dc_0       ; and 1, 2: the degree-0 color
;;   property float f_rest_0     ; ... the higher degrees, red's then
;;                               ;     green's then blue's, if any
;;   property float opacity      ; a logit
;;   property float scale_0      ; and 1, 2: log standard deviations
;;   property float rot_0        ; and 1, 2, 3: a quaternion w, x, y, z
;;   end_header
;;
;; Other float properties, such as normals, are skipped. `read-ply` parses
;; the header into where each property sits, then activates each gaussian
;; as `Gaussian` expects: scales through exp, the opacity through the
;; sigmoid, and the quaternion normalized. Every gaussian is given the same
;; row of the transforms table, so a file is one posable cloud.
;;
;; `write-ply` writes the file the reference implementation would, its
;; properties in the reference's order with a zero normal after the
;; center, so what reads the reference's files reads these.
(define-library (snail shell graphics ply)
  (export
   read-ply
   Trained
   write-ply)
  (import
   (snail core base)
   (only (snail shell math) exp)
   (snail shell graphics pod)
   (snail shell graphics splat))
  (begin

    ;; ---- The header ----

    ;; Where a file's floats begin, how many vertices it has and how many
    ;; floats each, and where each property this reader uses sits among
    ;; them: the center, the degree-0 color, the higher degrees'
    ;; coefficients of each channel in turn, the opacity, the scales and
    ;; the quaternion.
    (record Properties
      ((start I64)
       (count I64)
       (stride I64)
       (position (List I64))
       (dc (List I64))
       (rest (List I64))
       (opacity I64)
       (scale (List I64))
       (rotation (List I64))))

    ;; The header's bytes run to the end of its `end_header` line.

    (define (header-end (bytes Bytes)) (→ (Option I64))
      (let ((marker (map char->i32 (string->list "end_header\n"))))
        (find-bytes bytes marker 0 (min (array-length bytes) 65536))))

    (define (find-bytes (bytes Bytes) (marker (List I32)) (at I64) (limit I64)) (→ (Option I64))
      (cond ((> (+ at (length marker)) limit) (None))
            ((bytes-at? bytes marker at) (Some (+ at (length marker))))
            (else (find-bytes bytes marker (+ at 1) limit))))

    (define (bytes-at? (bytes Bytes) (marker (List I32)) (at I64)) (→ Bool)
      (match marker
        ((Nil) #t)
        ((Cons byte rest)
         (and (= (u8->i32 (array-ref bytes at)) byte) (bytes-at? bytes rest (+ at 1))))))

    ;; Each line of the header, as its words.

    (define (header-lines (bytes Bytes) (end I64)) (→ (List (List String)))
      (map (lambda (line) (filter (lambda (word) (not (string=? word ""))) (split line #\space)))
           (split
            (list->string (map (lambda (index) (integer->char (u8->i64 (array-ref bytes index))))
                               (iota end)))
            #\newline)))

    (define (u8->i64 (byte U8)) (→ I64) (i32->i64 (u8->i32 byte)))

    (define (split (text String) (separator Char)) (→ (List String))
      (match (string-index text separator)
        ((Some at)
         (Cons (substring text 0 at)
               (split (substring text (+ at 1) (string-length text)) separator)))
        ((None) (list text))))

    ;; Whether a line begins with these words.

    (define (begins? (line (List String)) (words (List String))) (→ Bool)
      (match words
        ((Nil) #t)
        ((Cons word rest)
         (match line
           ((Cons first more) (and (string=? first word) (begins? more rest)))
           ((Nil) #f)))))

    ;; The vertex count and the names of its properties, in order, from a
    ;; binary little-endian header whose vertex properties are all floats.

    (define (vertex-element (lines (List (List String))))
      (→ (Result (Pair I64 (List String)) String))
      (cond ((not (and (not (null? lines)) (begins? (list-ref lines 0) (list "ply"))))
             (Err "ply: not a PLY file"))
            ((not (any? (lambda (line) (begins? line (list "format" "binary_little_endian")))
                        lines))
             (Err "ply: only binary little-endian PLY files are read"))
            (else
             (match (list-index (lambda (line) (begins? line (list "element" "vertex"))) lines)
               ((Some at)
                (match (string->i64 (list-ref (list-ref lines at) 2))
                  ((Some count) (property-names count (list-tail lines (+ at 1)) (Nil)))
                  ((None) (Err "ply: the vertex count is not a number"))))
               ((None) (Err "ply: the file has no vertex element"))))))

    ;; Property lines up to the next element or the header's end.

    (define (property-names (count I64) (lines (List (List String))) (names (List String)))
      (→ (Result (Pair I64 (List String)) String))
      (match lines
        ((Cons line rest)
         (cond ((and (begins? line (list "property" "float")) (= (length line) 3))
                (property-names count rest (Cons (list-ref line 2) names)))
               ((begins? line (list "property")) (Err "ply: every vertex property must be a float"))
               (else (Ok (new Pair (first count) (second (reverse names)))))))
        ((Nil) (Ok (new Pair (first count) (second (reverse names)))))))

    ;; Where each property this reader uses sits among the names.

    (define (properties (start I64) (count I64) (names (List String)))
      (→ (Result Properties String))
      (let* ((index (lambda (name) (list-index (lambda (other) (string=? other name)) names)))
             (all (lambda (prefix n)
                    (map (lambda (k) (index (string-append prefix (show k)))) (iota n))))
             (rest (filter (lambda (name)
                             (and (> (string-length name) 7)
                                  (string=? (substring name 0 7) "f_rest_")))
                           names))
             (wanted (concatenate
                      (list (list (index "x") (index "y") (index "z") (index "opacity"))
                            (all "f_dc_" 3)
                            (all "scale_" 3)
                            (all "rot_" 4)
                            (all "f_rest_" (length rest))))))
        (match (present wanted)
          ((None) (Err "ply: a 3D Gaussian Splatting property is missing"))
          ((Some at)
           (if (any? (lambda (n) (= n (length rest))) (list 0 9 24 45))
               (Ok (placed start count (length names) at))
               (Err "ply: the f_rest properties are no whole degree of harmonics"))))))

    ;; Every index, if each was found.

    (define (present (indices (List (Option I64)))) (→ (Option (List I64)))
      (match indices
        ((Nil) (Some (Nil)))
        ((Cons (Some at) rest)
         (match (present rest)
           ((Some found) (Some (Cons at found)))
           ((None) (None))))
        ((Cons (None) _) (None))))

    ;; The indices in the order `properties` asked for them.

    (define (placed (start I64) (count I64) (stride I64) (at (List I64))) (→ Properties)
      (new Properties
        (start start)
        (count count)
        (stride stride)
        (position (take at 3))
        (dc (take (list-drop at 4) 3))
        (rest (list-drop at 14))
        (opacity (list-ref at 3))
        (scale (take (list-drop at 7) 3))
        (rotation (take (list-drop at 10) 4))))

    ;; ---- Reading ----

    ;; A file's gaussians, every one on row `transform`.

    (define (read-ply (bytes Bytes) (transform I32)) (→ (Result Cloud String))
      (match (header-end bytes)
        ((None) (Err "ply: the header has no end_header line"))
        ((Some start)
         (match (vertex-element (header-lines bytes start))
           ((Err message) (Err message))
           ((Ok element)
            (match (properties start (● element first) (● element second))
              ((Err message) (Err message))
              ((Ok p)
               (if (< (array-length bytes) (+ start (* 4 (* (● p count) (● p stride)))))
                   (Err "ply: the file ends before its last vertex")
                   (Ok (cloud-of bytes p transform))))))))))

    ;; Each gaussian and its coefficients written where the GPU reads them,
    ;; into arrays local to this call.

    (define (cloud-of (bytes Bytes) (p Properties) (transform I32)) (→ Cloud)
      (unsafe-total
       (lambda ()
         (let ((gaussians (make-array (* (● p count) (stride gaussian-shape)) (i32->u8 0)))
               (harmonics (make-array (* (● p count) (* 4 harmonic-floats)) (i32->u8 0))))
           (for-each (lambda (i)
                       (let ((float (lambda (property) (float-at bytes p i property))))
                         (pod-write (gaussian-of float p transform)
                                    gaussians
                                    (* i (stride gaussian-shape)))
                         (write-harmonics! harmonics i (coefficients float p))))
                     (iota (● p count)))
           (new Cloud (count (● p count)) (gaussians gaussians) (harmonics harmonics))))))

    ;; Vertex i's float at property index `property`, little-endian.

    (define (float-at (bytes Bytes) (p Properties) (i I64) (property I64)) (→ F32)
      (let* ((at (+ (● p start) (* 4 (+ (* i (● p stride)) property))))
             (byte (lambda (k shift) (i32-shift-left (u8->i32 (array-ref bytes (+ at k))) shift))))
        (bits->f32 (i32-or (i32-or (byte 0 0) (byte 1 8)) (i32-or (byte 2 16) (byte 3 24))))))

    (define (gaussian-of (float (Fn I64 → F32)) (p Properties) (transform I32)) (→ Gaussian)
      (let ((v (lambda (indices) (map (lambda (index) (f32->f64 (float index))) indices))))
        (new Gaussian
          (position (vec3 (v (● p position))))
          (transform transform)
          (rotation (quaternion (v (● p rotation))))
          (scale (vec3 (map exp (v (● p scale)))))
          (opacity (f64->f32 (/ 1.0 (+ 1.0 (exp (negate (f32->f64 (float (● p opacity))))))))))))

    (define (vec3 (v (List F64))) (→ Vec3f)
      (new Vec3f
        (x (f64->f32 (list-ref v 0)))
        (y (f64->f32 (list-ref v 1)))
        (z (f64->f32 (list-ref v 2)))))

    ;; A file's w, x, y, z, normalized, as x, y, z, w.

    (define (quaternion (q (List F64))) (→ Vec4f)
      (let ((l (sqrt (fold-left (lambda (sum x) (+ sum (* x x))) 0.0 q))))
        (new Vec4f
          (x (f64->f32 (/ (list-ref q 1) l)))
          (y (f64->f32 (/ (list-ref q 2) l)))
          (z (f64->f32 (/ (list-ref q 3) l)))
          (w (f64->f32 (/ (list-ref q 0) l))))))

    ;; The colors of the coefficients, from degree 0: coefficient k > 0 of
    ;; channel c is the file's f_rest at c times the coefficients a channel
    ;; has above degree 0, plus k - 1.

    (define (coefficients (float (Fn I64 → F32)) (p Properties)) (→ (List F32))
      (let ((above (quotient (length (● p rest)) 3)))
        (append (map float (● p dc))
                (concatenate (map (lambda (k)
                                    (map
                                     (lambda (c) (float (list-ref (● p rest) (+ (* c above) k))))
                                     (iota 3)))
                                  (iota above))))))

    (define (write-harmonics! (harmonics Bytes) (i I64) (floats (List F32))) (→ Unit) (! mut)
      (fold-left (lambda (at value) (pod-write value harmonics at))
                 (* i (* 4 harmonic-floats))
                 floats)
      (unit))

    ;; ---- Writing ----

    ;; A cloud as training keeps it, each array a row a gaussian of
    ;; little-endian F32s, nothing activated: whether the row is a
    ;; gaussian, 1 or 0; its center; its log standard deviations; its
    ;; quaternion x, y, z, w, of any length; its opacity's logit; and its
    ;; harmonics' coefficients a degree, the 1, 3, 5 and 7 of them each
    ;; red, green and blue. The reference's file holds the same values,
    ;; so they are written as they are.
    (record Trained
      ((live Bytes)
       (centers Bytes)
       (scales Bytes)
       (rotations Bytes)
       (opacities Bytes)
       (dc Bytes)
       (degree1 Bytes)
       (degree2 Bytes)
       (degree3 Bytes)))

    ;; One of a trained cloud's arrays, and where each float of its row
    ;; goes among a vertex's.
    (record Column
      ((floats Bytes)
       (places (Array I64))))

    ;; A vertex's floats: the center, a normal, the degree-0 color, 15
    ;; higher coefficients a channel, the opacity, the scales and the
    ;; quaternion.
    (define vertex-floats (→ I64) 62)

    (define (written-names) (→ (List String))
      (let ((numbered
             (lambda (prefix n) (map (lambda (k) (string-append prefix (show k))) (iota n)))))
        (concatenate (list (list "x" "y" "z" "nx" "ny" "nz")
                           (numbered "f_dc_" 3)
                           (numbered "f_rest_" 45)
                           (list "opacity")
                           (numbered "scale_" 3)
                           (numbered "rot_" 4)))))

    (define (written-header (count I64)) (→ Bytes)
      (let ((lines (concatenate
                    (list (list "ply"
                                "format binary_little_endian 1.0"
                                (string-append "element vertex " (show count)))
                          (map (lambda (name) (string-append "property float " name))
                               (written-names))
                          (list "end_header" "")))))
        (list->array (map (lambda (char) (i32->u8 (char->i32 char)))
                          (string->list (string-join lines "\n"))))))

    ;; The columns of a trained cloud. The file's f_rest holds red's 15
    ;; coefficients above degree 0, then green's, then blue's, and degree
    ;; d's 2 d + 1 follow the d² - 1 of the degrees below it, so its
    ;; coefficient j of channel c is f_rest 15 c + d² - 1 + j, vertex float
    ;; 9 more. A quaternion's w goes first. No column names the normal's
    ;; floats, 3 to 5, which stay the zeros the file is made of.
    (define (columns (cloud Trained)) (→ (List Column))
      (let ((column (lambda (floats places)
                      (new Column (floats floats) (places (list->array places)))))
            (higher (lambda (d)
                      (concatenate (map (lambda (j)
                                          (map (lambda (c) (+ 8 (+ (* 15 c) (+ (* d d) j))))
                                               (iota 3)))
                                        (iota (+ 1 (* 2 d))))))))
        (list (column (● cloud centers) (list 0 1 2))
              (column (● cloud dc) (list 6 7 8))
              (column (● cloud degree1) (higher 1))
              (column (● cloud degree2) (higher 2))
              (column (● cloud degree3) (higher 3))
              (column (● cloud opacities) (list 54))
              (column (● cloud scales) (list 55 56 57))
              (column (● cloud rotations) (list 59 60 61 58)))))

    (define (live? (cloud Trained) (i I64)) (→ Bool)
      (not (= (u8->i32 (array-ref (● cloud live) (+ (* 4 i) 3))) 0)))

    (define (live-count (cloud Trained)) (→ I64)
      (let loop ((i 0) (count 0))
        (if (< i (quotient (array-length (● cloud live)) 4))
            (loop (+ i 1) (if (live? cloud i) (+ count 1) count))
            count)))

    ;; The file of a trained cloud's live gaussians, in their order: its
    ;; header, which says how many, then each one's floats.
    (define (write-ply (cloud Trained)) (→ Bytes)
      (let* ((count (live-count cloud)) (head (written-header count)) (columns (columns cloud)))
        (unsafe-total
         (lambda ()
           (let ((file (make-array (+ (array-length head) (* count (* 4 vertex-floats)))
                                   (i32->u8 0))))
             (array-copy! file 0 head 0 (array-length head))
             (let loop ((i 0) (at (array-length head)))
               (cond ((>= i (quotient (array-length (● cloud live)) 4)) file)
                     ((live? cloud i)
                      (for-each (lambda (column) (place! file at column i)) columns)
                      (loop (+ i 1) (+ at (* 4 vertex-floats))))
                     (else (loop (+ i 1) at)))))))))

    ;; Row `i` of a column, each float where it goes in the vertex at `at`.
    (define (place! (file Bytes) (at I64) (column Column) (i I64)) (→ Unit) (! mut)
      (let ((width (array-length (● column places))))
        (let loop ((k 0))
          (when (< k width)
            (array-copy! file
                         (+ at (* 4 (array-ref (● column places) k)))
                         (● column floats)
                         (* 4 (+ (* i width) k))
                         4)
            (loop (+ k 1))))))

    ))
