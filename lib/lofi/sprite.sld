;; Spritebooks: animations drawn on a picture divided into equal cells, by
;; motion and heading, posed as sprites standing in a 3D scene. Nothing here
;; knows a particular sheet. A sheet's own library says which cells each
;; motion uses and in which order the sheet draws its headings; this library
;; picks the heading a viewer should see and places the sprite.
(define-library (lofi sprite)
  (export
   Strip
   Spritebook
   Spritebook-picture
   strip-texture
   heading
   pose)
  (import
   (lofi base)
   (lofi app)
   (lofi math))
  (begin

    ;; ---- Strips ----

    ;; A row of `frames` cells from (column, row) rightward, each shown for
    ;; `period` milliseconds. A single frame is a still.
    (struct Strip
      ((column I32)
       (row I32)
       (frames I32)
       (period I32)))

    ;; ---- Spritebooks ----

    ;; A picture divided into `cell-width` by `cell-height` cells, showing a
    ;; figure from `headings` evenly spaced directions. `strip` gives the cells
    ;; for a motion seen from heading h, where heading 0 faces the viewer and
    ;; each next one turns a step toward the viewer's right. Being a
    ;; function of every motion, a book cannot lack one; a sheet without some
    ;; motion maps it to another.
    (struct (Spritebook M)
      ((picture I32)
       (cell-width I32)
       (cell-height I32)
       (headings I64)
       (strip (-> M I64 Strip))))

    (: strip-texture (All (M) (-> (Spritebook M) Strip Texture)))
    (define (strip-texture book strip)
      (let ((width (Spritebook-cell-width book)) (height (Spritebook-cell-height book)))
        (Texture (Spritebook-picture book) (Rect (* width (Strip-column strip)) (* height (Strip-row strip)) width height)
                 (Strip-frames strip) (Strip-period strip))))

    ;; ---- Headings ----

    ;; Which of `count` headings shows a figure facing `facing`, a direction
    ;; on the ground, to `camera`: 0 when it faces the viewer, a quarter of
    ;; `count` when it faces the viewer's right, and so on around. The angle
    ;; is measured against the camera's view, so turning the camera turns
    ;; every figure with it.
    (: heading (-> I64 Vec3 Camera I64))
    (define (heading count facing camera)
      (let* ((eye (Camera-eye camera)) (target (Camera-target camera))
             (fx (f32->f64 (- (Vec3-x target) (Vec3-x eye)))) (fz (f32->f64 (- (Vec3-z target) (Vec3-z eye))))
             (x (f32->f64 (Vec3-x facing))) (z (f32->f64 (Vec3-z facing)))
             (toward (negate (+ (* x fx) (* z fz)))) (right (- (* z fx) (* x fz)))
             (step (/ (* 2.0 pi) (i64->f64 count))))
        (modulo (f64->i64 (round (/ (atan2 right toward) step))) count)))

    ;; ---- Poses ----

    ;; The book's motion seen from the heading `camera` gives a figure facing
    ;; `facing`, as a sprite `height` world units tall with its bottom center
    ;; at `position`. Its width keeps the cells' proportions.
    (: pose (All (M) (-> (Spritebook M) M Vec3 Vec3 F32 Camera Item)))
    (define (pose book motion position facing height camera)
      (let ((strip ((Spritebook-strip book) motion (heading (Spritebook-headings book) facing camera))))
        (sprite (strip-texture book strip) position
                (/ (* height (i32->f32 (Spritebook-cell-width book))) (i32->f32 (Spritebook-cell-height book))) height)))

    ))
