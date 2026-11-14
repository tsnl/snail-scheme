;; The geometry of LPC character sheets. The universal sheet is 832 by 1344
;; pixels of 64-pixel cells: four rows each of casting (7 frames), thrusting
;; (8), walking (9) and slashing (6), four of shooting (13), and one row of
;; falling hurt (6). Each motion's four rows face away from the viewer,
;; left, toward the viewer and right, in that order. Every LPC pack uses this
;; grid, so layers drawn for it line up.
(define-library (lpc layout)
  (export
   Motion
   Cast
   Thrust
   Walk
   Slash
   Shoot
   Hurt
   Gait
   Stand
   Stroll
   walk-region
   universal-book
   walk-book
   face-region)
  (import
   (snail core base)
   (snail shell app)
   (snail shell sprite))
  (begin

    ;; ---- Cells ----

    (define (cell) (→ I32) 64)

    ;; The four walking rows alone. Their first frame is the figure standing
    ;; still; the other eight are its stride.
    (define (walk-region) (→ Rect) (new Rect (x 0) (y 512) (width 576) (height 256)))

    ;; The row within a motion's four for a spritebook heading: heading 0
    ;; faces the viewer (the sheet's third row), 1 their right (the fourth),
    ;; 2 away (the first) and 3 their left (the second).
    (define (heading-row (heading I64)) (→ I32)
      (list-ref (list 2 3 0 1) (modulo heading 4)))

    ;; ---- The universal sheet ----

    (enum Motion
      (Cast)
      (Thrust)
      (Walk)
      (Slash)
      (Shoot)
      (Hurt))

    ;; A motion's first row, frame count and milliseconds per frame. Hurt has
    ;; one row, seen from every heading.
    (define (motion-strip (motion Motion) (heading I64)) (→ Strip)
      (match motion
        ((Cast) (new Strip (column 0) (row (heading-row heading)) (frames 7) (period 100)))
        ((Thrust) (new Strip (column 0) (row (+ 4 (heading-row heading))) (frames 8) (period 80)))
        ((Walk) (new Strip (column 1) (row (+ 8 (heading-row heading))) (frames 8) (period 90)))
        ((Slash) (new Strip (column 0) (row (+ 12 (heading-row heading))) (frames 6) (period 80)))
        ((Shoot) (new Strip (column 0) (row (+ 16 (heading-row heading))) (frames 13) (period 70)))
        ((Hurt) (new Strip (column 0) (row 20) (frames 6) (period 100)))))

    ;; A picture holding a whole universal sheet.
    (define (universal-book (picture I32)) (→ (Spritebook Motion))
      (new Spritebook
        (picture picture)
        (cell-width (cell))
        (cell-height (cell))
        (headings 4)
        (strip motion-strip)))

    ;; ---- The walking rows ----

    ;; What a picture of only the walking rows can show.
    (enum Gait
      (Stand)
      (Stroll))

    (define (gait-strip (gait Gait) (heading I64)) (→ Strip)
      (match gait
        ((Stand) (new Strip (column 0) (row (heading-row heading)) (frames 1) (period 1)))
        ((Stroll) (new Strip (column 1) (row (heading-row heading)) (frames 8) (period 90)))))

    ;; A picture holding `walk-region` of a sheet, at its top left.
    (define (walk-book (picture I32)) (→ (Spritebook Gait))
      (new Spritebook
        (picture picture)
        (cell-width (cell))
        (cell-height (cell))
        (headings 4)
        (strip gait-strip)))

    ;; In such a picture, the standing figure facing the viewer from the
    ;; shoulders up, room left for tall hair: a portrait.
    (define (face-region) (→ Rect) (new Rect (x 12) (y 130) (width 40) (height 40)))

    ))
