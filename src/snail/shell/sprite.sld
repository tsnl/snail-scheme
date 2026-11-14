;; Spritebooks: animations drawn on a picture divided into equal cells, by
;; motion and heading, posed as sprites standing in a 3D scene. Nothing here
;; knows a particular sheet. A sheet's own library says which cells each
;; motion uses and in which order the sheet draws its headings; this library
;; picks the heading a viewer should see and places the sprite.
(define-library (snail shell sprite)
  (export
   Strip
   Spritebook
   heading
   pose
   pose-flat)
  (import
   (snail core base)
   (snail shell app)
   (snail shell math))
  (begin

    ;; ---- Strips ----

    ;; A row of `frames` cells from (column, row) rightward, each shown for
    ;; `period` milliseconds. A single frame is a still.
    (record Strip
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
    (record (Spritebook M)
      ((picture I32)
       (cell-width I32)
       (cell-height I32)
       (headings I64)
       (strip (Fn M I64 → Strip))))

    (define (strip-texture (book (Spritebook M)) (strip Strip)) (→ Texture) (∀ (M))
      (let ((width (● book cell-width)) (height (● book cell-height)))
        (new Texture (picture (● book picture))
             (region (new Rect
                       (x (* width (● strip column)))
                       (y (* height (● strip row)))
                       (width width)
                       (height height)))
             (frames (● strip frames)) (period (● strip period)))))

    ;; ---- Headings ----

    ;; Which of `count` headings shows a figure facing `facing`, a direction
    ;; on the ground, to `camera`: 0 when it faces the viewer, a quarter of
    ;; `count` when it faces the viewer's right, and so on around. Toward the
    ;; viewer is down the screen, so this holds for a camera tilted down and
    ;; for one looking straight down at a map alike, and turning the camera
    ;; turns every figure with it. The screen's right lies on the ground for
    ;; any camera without roll, and down the screen is a quarter turn from
    ;; it: (-rz, rx) on the ground, which needs no projection that a level
    ;; or steep camera would shrink.

    (define (heading (count I64) (facing Vec3) (camera Camera)) (→ I64)
      (let* ((right (● (screen-axes camera) first))
             (rx (f32->f64 (● right x)))
             (rz (f32->f64 (● right z)))
             (x (f32->f64 (● facing x))) (z (f32->f64 (● facing z)))
             (step (/ (* 2.0 (pi)) (i64->f64 count))))
        (modulo (f64->i64 (round (/ (atan2 (+ (* x rx) (* z rz)) (- (* z rx) (* x rz))) step)))
                count)))

    ;; ---- Poses ----

    ;; The book's motion seen from the heading `camera` gives a figure facing
    ;; `facing`, as a sprite `height` world units tall with its bottom center
    ;; at `position`. Its width keeps the cells' proportions.

    (define (pose (book (Spritebook M))
                  (motion M)
                  (position Vec3)
                  (facing Vec3)
                  (height F32)
                  (camera Camera))
      (→ Item)
      (∀ (M))
      (sprite (posed-texture book motion facing camera)
              position
              (cell-width-for book height)
              height))

    ;; The same, lying flat on the ground for a camera looking straight
    ;; down: a figure on a 2D map.

    (define (pose-flat (book (Spritebook M))
                       (motion M)
                       (position Vec3)
                       (facing Vec3)
                       (height F32)
                       (camera Camera))
      (→ Item)
      (∀ (M))
      (flat-sprite (posed-texture book motion facing camera)
                   position
                   (cell-width-for book height)
                   height))

    (define (posed-texture (book (Spritebook M)) (motion M) (facing Vec3) (camera Camera))
      (→ Texture)
      (∀ (M))
      (strip-texture book
                     ((● book strip)
                      motion
                      (heading (● book headings) facing camera))))

    ;; The width that keeps a cell's proportions at `height`.

    (define (cell-width-for (book (Spritebook M)) (height F32)) (→ F32) (∀ (M))
      (/ (* height (i32->f32 (● book cell-width)))
         (i32->f32 (● book cell-height))))

    ))
