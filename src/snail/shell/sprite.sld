;; Spritebooks: animations drawn on a picture divided into equal cells, by
;; motion and heading. Nothing here knows a particular sheet or how a cell
;; is drawn. A sheet's own library says which cells each motion uses and in
;; which order the sheet draws its headings; this library picks the heading
;; a viewer should see and the cell a strip shows at a moment, which a
;; quad then shows (`(snail shell graphics quad)`).
(define-library (snail shell sprite)
  (export
   Strip
   Spritebook
   heading
   cell-at)
  (import
   (snail core base)
   (only (snail shell graphics atlas) Rect)
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

    ;; ---- Headings ----

    ;; Which of `count` headings shows a figure facing (x, y) in the plane
    ;; of the screen, up being +y: 0 when it faces the viewer, down the
    ;; screen, a quarter of `count` when it faces the viewer's right, and
    ;; so on around.
    (define (heading (count I64) (x F64) (y F64)) (→ I64)
      (let ((step (/ (* 2.0 pi) (i64->f64 count))))
        (modulo (f64->i64 (round (/ (atan2 x (negate y)) step))) count)))

    ;; ---- Cells ----

    ;; The cell the book's motion shows from `heading` at `time`
    ;; milliseconds: its strip's frames take turns by the clock.
    (define (cell-at (book (Spritebook M)) (motion M) (heading I64) (time I64)) (→ Rect) (∀ (M))
      (let* ((strip ((● book strip) motion heading))
             (frame (modulo (quotient time (i32->i64 (max 1 (● strip period))))
                            (i32->i64 (max 1 (● strip frames))))))
        (new Rect
          (x (* (● book cell-width) (+ (● strip column) (i64->i32 frame))))
          (y (* (● book cell-height) (● strip row)))
          (width (● book cell-width))
          (height (● book cell-height)))))

    ))
