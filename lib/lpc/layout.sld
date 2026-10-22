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
   cell
   universal-region
   walk-region
   universal-book
   walk-book
   face-region)
  (import
   (lofi base)
   (lofi app)
   (lofi sprite))
  (begin

    ;; ---- Cells ----

    (define cell 64)

    (define universal-region (Rect 0 0 832 1344))

    ;; The four walking rows alone. Their first frame is the figure standing
    ;; still; the other eight are its stride.
    (define walk-region (Rect 0 512 576 256))

    ;; The row within a motion's four for a spritebook heading: heading 0
    ;; faces the viewer (the sheet's third row), 1 their right (the fourth),
    ;; 2 away (the first) and 3 their left (the second).
    (: heading-row (-> I64 I32))
    (define (heading-row heading)
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
    (: motion-strip (-> Motion I64 Strip))
    (define (motion-strip motion heading)
      (match motion
        ((Cast) (Strip 0 (heading-row heading) 7 100))
        ((Thrust) (Strip 0 (+ 4 (heading-row heading)) 8 80))
        ((Walk) (Strip 1 (+ 8 (heading-row heading)) 8 90))
        ((Slash) (Strip 0 (+ 12 (heading-row heading)) 6 80))
        ((Shoot) (Strip 0 (+ 16 (heading-row heading)) 13 70))
        ((Hurt) (Strip 0 20 6 100))))

    ;; A picture holding a whole universal sheet.
    (: universal-book (-> I32 (Spritebook Motion)))
    (define (universal-book picture)
      (Spritebook picture cell cell 4 motion-strip))

    ;; ---- The walking rows ----

    ;; What a picture of only the walking rows can show.
    (enum Gait
      (Stand)
      (Stroll))

    (: gait-strip (-> Gait I64 Strip))
    (define (gait-strip gait heading)
      (match gait
        ((Stand) (Strip 0 (heading-row heading) 1 1))
        ((Stroll) (Strip 1 (heading-row heading) 8 90))))

    ;; A picture holding `walk-region` of a sheet, at its top left.
    (: walk-book (-> I32 (Spritebook Gait)))
    (define (walk-book picture)
      (Spritebook picture cell cell 4 gait-strip))

    ;; In such a picture, the standing figure facing the viewer from the
    ;; shoulders up, room left for tall hair: a portrait.
    (define face-region (Rect 12 130 40 40))

    ))
