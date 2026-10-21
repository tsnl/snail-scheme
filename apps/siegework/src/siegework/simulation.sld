;; The two ways the world changes: `act` applies a player's order, and
;; `advance` runs one tick of the rules. Nothing else produces a World, so
;; the colony depends only on its seed and the orders given at each tick.
(define-library (siegework simulation)
  (export
   act
   advance)
  (import
   (lofi base)
   (siegework world)
   (siegework colony)
   (siegework siege))
  (begin

    ;; ---- Ticks ----

    ;; Nothing happens until the first extractor is ordered, or once the
    ;; game is decided. Production and work come first, so new buildings
    ;; act this tick; damage is removed only at the end, so everything alive
    ;; at the start of a tick acts.
    (: advance (-> World World))
    (define (advance world)
      (if (and (World-started world) (playing? world))
          (judge (clean-up (fire-turrets (update-enemies (spawn-waves (work (produce (World-tick-set world (+ (World-tick world) 1)))))))))
          world))

    ))
