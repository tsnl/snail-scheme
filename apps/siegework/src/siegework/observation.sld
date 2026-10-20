;; Player observations are authored beside the model, not decoded from World
;; by a host. Rows cross one read-only scalar transaction; no scene is rendered.
(define-library (siegework observation)
  (export observe-player!)
  (import
   (scheme base)
   (siegework model)
   (siegework terrain)
   (only (lofi core) define-extern -> I32))
  (begin
    (define-extern row! "snail.reducer" "observe" (-> I32 I32 I32 I32 I32 I32 I32 Unit))

    ;; ---- Public colony facts ----

    ;; Tags and field names are decoded in headless.mjs. This version describes
    ;; player knowledge, independently of the privileged inspection projection.
    (define (observe-colony! world)
      (row! 0 1 map-width map-height cell-size simulation-ticks-per-second (world-seed world))
      (row! 1 (world-tick world) (world-outcome world) (world-paused world)
            (if (world-started world) 1 0) (world-credits world) (world-hull world))
      (row! 2 (world-produced world) (world-delivered world) (world-spent world)
            (world-lost-ore world) (world-kills world) (world-casualties world))
      (row! 3 (world-hub-x world) (world-hub-y world) (world-hub-capacity-level world)
            (worker-capacity world) (pending-workers (world-bots world)) (world-notice world))
      (row! 4 (fabrication-reason world) (repair-reason world) (hub-upgrade-reason world) 0 0 0))

    ;; ---- Known geography and current sight ----

    ;; Outside current sight only seeded geography is reported. Dynamic rock
    ;; damage and underground reserves are unknown (-1), never omniscient data.
    (define (terrain-kind world x y visible)
      (cond ((if visible (world-ground? world x y) (ground? (world-seed world) x y)) 1)
            ((water? (world-seed world) x y) 2)
            (else 0)))
    (define (observe-build! world cell kind)
      (when (= (placement-reason world kind (index-x cell) (index-y cell)) 0)
        (row! 60 cell kind 0 0 0 0)))
    (define (observe-cell! world cell)
      (let* ((x (index-x cell)) (y (index-y cell)) (visible (visible? world x y)))
        (row! 10 cell (if visible 1 0) (terrain-kind world x y visible)
              (world-deposit-rate world x y)
              (if visible (ore-remaining world x y) -1)
              (if visible (world-rock-remaining world x y) -1))
        ;; These are previews, as in the UI. The paid command additionally
        ;; proves walking routes and kit ownership before accepting an order.
        (when visible (observe-build! world cell 1) (observe-build! world cell 2) (observe-build! world cell 3))))
    (define (observe-map! world)
      (let loop ((cell 0))
        (when (< cell (* map-width map-height))
          (when (known? world (index-x cell) (index-y cell)) (observe-cell! world cell))
          (loop (+ cell 1)))))

    ;; ---- Owned entities and visible hostiles ----

    (define (observe-building! world building)
      (unless (construction-hidden? world building)
        (row! 20 (building-id building) (building-kind building)
              (cell-index (building-x building) (building-y building))
              (building-level building) (building-hp building) (building-stage building))
        (row! 21 (building-id building) (building-stock building) (building-armed building)
              (building-cooldown building) (building-move-x building) (building-move-y building))
        (row! 22 (building-id building) (scavenge-refund building)
              (if (scavenge-pending? world (building-id building)) 1 0) 0 0 0)))
    (define (observe-buildings! world buildings)
      (unless (null? buildings)
        (observe-building! world (car buildings)) (observe-buildings! world (cdr buildings))))
    (define (observe-workers! bots)
      (unless (null? bots)
        (let ((bot (car bots)))
          (row! 30 (bot-id bot) (bot-x bot) (bot-y bot) (bot-hp bot) (bot-job bot) (bot-cargo bot)))
        (observe-workers! (cdr bots))))
    (define (observe-enemies! world enemies)
      (unless (null? enemies)
        (let ((enemy (car enemies)))
          (when (visible? world (quotient (enemy-x enemy) cell-size) (quotient (enemy-y enemy) cell-size))
            (row! 40 (enemy-id enemy) (enemy-x enemy) (enemy-y enemy)
                  (enemy-hp enemy) (enemy-kind enemy) (enemy-rank enemy))))
        (observe-enemies! world (cdr enemies))))
    (define (observe-nests! world nests)
      (unless (null? nests)
        (let* ((nest (car nests)) (x (nest-site-x nest)) (y (nest-site-y nest)))
          (when (known? world x y)
            (row! 50 (nest-id nest) (cell-index x y)
                  (if (visible? world x y) (nest-hp nest) -1) 0 0 0)))
        (observe-nests! world (cdr nests))))
    (define (observe-player! world)
      (observe-colony! world)
      (observe-map! world)
      (observe-buildings! world (world-buildings world))
      (observe-workers! (world-bots world))
      (observe-enemies! world (world-enemies world))
      (observe-nests! world (world-nests world)) 1)))
