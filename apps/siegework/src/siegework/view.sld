;; What the player sees: the map, buildings and units as mesh instances,
;; and the HUD. Batches are versioned so the host redraws the map only
;; when it changes.
(define-library (siegework view)
  (export
   view-game)
  (import
   (lofi base)
   (lofi app)
   (lofi math)
   (siegework grid)
   (siegework world)
   (siegework game))
  (begin

    ;; ---- Placement ----

    (: cell-point (-> Cell F32 Vec3))
    (define (cell-point cell height)
      (Vec3 (i64->f32 (Cell-x cell)) height (i64->f32 (Cell-y cell))))

    (: item (-> Mesh Vec3 F32 F32 F32 I32 Item))
    (define (item mesh position width height depth color)
      (Item mesh position (Vec3 width height depth) 0.0 color))

    ;; Between steps a unit is drawn partway from its previous cell.
    (: mover-point (-> Mover I64 F32 F32 Vec3))
    (define (mover-point mover speed alpha height)
      (let* ((progress (max 0.0 (min 1.0 (- 1.0 (/ (- (i64->f32 (Mover-wait mover)) alpha) (i64->f32 (- speed 1)))))))
             (from (cell-point (Mover-previous mover) height)) (to (cell-point (Mover-cell mover) height)))
        (Vec3 (+ (Vec3-x from) (* progress (- (Vec3-x to) (Vec3-x from))))
              height
              (+ (Vec3-z from) (* progress (- (Vec3-z to) (Vec3-z from)))))))

    ;; ---- Map ----

    (: terrain-items (-> World (List Item)))
    (define (terrain-items world)
      (map (lambda (index)
             (let ((cell (index-cell index)))
               (cond ((not (vector-ref (World-explored world) index)) (item (Tile) (cell-point cell 0.0) 1.0 0.05 1.0 (rgb 28 32 40)))
                     ((match (vector-ref (World-terrain world) index) ((Rock) #t) ((Open) #f))
                      (item (Box) (cell-point cell 0.0) 0.95 0.7 0.95 (rgb 105 100 96)))
                     (else (item (Tile) (cell-point cell 0.0) 1.0 0.1 1.0
                                 (if (= (remainder (+ (Cell-x cell) (Cell-y cell)) 2) 0) (rgb 74 104 66) (rgb 70 98 62)))))))
           (iota (* map-size map-size))))

    (: explored? (-> World Cell Bool))
    (define (explored? world cell)
      (vector-ref (World-explored world) (cell-index cell)))

    ;; ---- Structures ----

    (: building-items (-> Building (List Item)))
    (define (building-items building)
      (let* ((cell (Building-cell building)) (built? (match (Building-progress building) ((Built) #t) (_ #f)))
             (shade (lambda (color) (if built? color (rgb 120 120 130)))))
        (match (Building-kind building)
          ((Hub) (list (item (Box) (cell-point cell 0.1) 1.4 1.2 1.4 (rgb 70 120 200))
                       (item (Pyramid) (cell-point cell 1.3) 1.4 0.6 1.4 (rgb 220 220 230))))
          ((Extractor) (list (item (Prism) (cell-point cell 0.1) 0.8 (if built? 0.9 0.3) 0.8 (shade (rgb 210 150 60)))
                             (item (Box) (cell-point cell 0.1) 0.3 (* 0.06 (i64->f32 (Building-stock building))) 0.3 (rgb 240 200 80))))
          ((Tower) (list (item (Box) (cell-point cell 0.1) 0.5 (if built? 2.4 0.4) 0.5 (shade (rgb 80 190 180)))))
          ((Gun) (list (item (Prism) (cell-point cell 0.1) 0.9 0.5 0.9 (shade (rgb 160 70 70)))
                       (item (Sphere) (cell-point cell 0.6) 0.6 0.6 0.6 (shade (rgb 200 90 80))))))))

    (: structure-items (-> World (List Item)))
    (define (structure-items world)
      (append (concatenate (map building-items (World-buildings world)))
              (append (map (lambda (deposit)
                             (let ((size (+ 0.3 (* 0.0006 (i64->f32 (Deposit-reserve deposit))))))
                               (item (Pyramid) (cell-point (Deposit-cell deposit) 0.1) size size size (rgb 230 190 60))))
                           (filter (lambda (deposit) (and (explored? world (Deposit-cell deposit)) (> (Deposit-reserve deposit) 0)))
                                   (World-deposits world)))
                      (map (lambda (nest)
                             (let ((size (+ 0.6 (* 0.0015 (i64->f32 (Nest-hp nest))))))
                               (item (Sphere) (cell-point (Nest-cell nest) 0.0) size size size (rgb 120 30 40))))
                           (filter (lambda (nest) (explored? world (Nest-cell nest))) (World-nests world))))))

    ;; ---- Units ----

    (: unit-items (-> Game F32 (List Item)))
    (define (unit-items game alpha)
      (let ((world (Game-world game)))
        (append (concatenate (map (lambda (worker) (worker-items worker alpha)) (World-workers world)))
                (append (map (lambda (enemy) (item (Pyramid) (mover-point (Enemy-mover enemy) enemy-speed alpha 0.1) 0.5 0.6 0.5 (rgb 220 50 50)))
                             (World-enemies world))
                        (append (map shot-item (World-shots world)) (cursor-items game))))))

    (: worker-items (-> Worker F32 (List Item)))
    (define (worker-items worker alpha)
      (let ((point (mover-point (Worker-mover worker) worker-speed alpha 0.3)))
        (Cons (item (Sphere) point 0.4 0.4 0.4 (rgb 120 200 255))
              (if (> (Worker-cargo worker) 0)
                  (list (item (Box) (Vec3 (Vec3-x point) 0.7 (Vec3-z point)) 0.2 0.2 0.2 (rgb 240 200 80)))
                  (Nil)))))

    ;; A thin beam from the gun to its target, rotated to face it.
    (: shot-item (-> Shot Item))
    (define (shot-item shot)
      (let* ((from (cell-point (Shot-from shot) 0.8)) (to (cell-point (Shot-to shot) 0.4))
             (dx (- (Vec3-x to) (Vec3-x from))) (dz (- (Vec3-z to) (Vec3-z from))))
        (Item (Box) (Vec3 (/ (+ (Vec3-x from) (Vec3-x to)) 2.0) 0.6 (/ (+ (Vec3-z from) (Vec3-z to)) 2.0))
              (Vec3 (sqrt (+ (* dx dx) (* dz dz))) 0.08 0.08) (atan2-f32 (negate dz) dx) (rgb 255 230 120))))

    (: atan2-f32 (-> F32 F32 F32))
    (define (atan2-f32 y x)
      (f64->f32 (atan2 (f32->f64 y) (f32->f64 x))))

    (: cursor-items (-> Game (List Item)))
    (define (cursor-items game)
      (match (Game-hover game)
        ((Some cell)
         (list (item (Tile) (cell-point cell 0.1) 1.0 0.04 1.0
                     (match (Game-tool game) ((Place _) (rgb 120 240 120)) ((Select) (rgb 240 240 240))))))
        ((None) (Nil))))

    ;; ---- HUD ----

    (: status-panel (-> World Panel))
    (define (status-panel world)
      (Panel (TopLeft)
             (list (Label (string-append "Ore " (show (World-ore world))))
                   (Label (string-append "Workers " (show (length (World-workers world)))))
                   (Label (string-append "Nests " (show (length (World-nests world)))))
                   (Meter (string-append "Next wave in " (show (quotient (ticks-until-wave world) 10)) "s")
                          (- 1.0 (/ (i64->f32 (ticks-until-wave world)) 450.0)))
                   (Label (World-message world)))))

    (: tool-panel (-> Game Panel))
    (define (tool-panel game)
      (let ((tool-button (lambda (kind)
                           (Button (string-append (kind-name kind) " " (show (kind-cost kind))) (action-tool kind)
                                   (match (Game-tool game) ((Place selected) (= (action-tool selected) (action-tool kind))) ((Select) #f))))))
        (Panel (BottomLeft)
               (list (tool-button (Extractor)) (tool-button (Tower)) (tool-button (Gun))
                     (Button "Worker 40" action-recruit #f)
                     (Button (if (Game-paused game) "Resume" "Pause") action-pause (Game-paused game))
                     (Button "New map" action-new-map #f)))))

    (: inspect-panel (-> Game Panel))
    (define (inspect-panel game)
      (let ((world (Game-world game)))
        (Panel (TopRight)
               (match (Game-hover game)
                 ((Some cell)
                  (Cons (Label (string-append "Cell " (show (Cell-x cell)) ", " (show (Cell-y cell))))
                        (append (map (lambda (b) (Label (string-append (kind-name (Building-kind b)) " · health " (show (Building-hp b))
                                                                      (match (Building-progress b) ((Built) "") (_ " · awaiting construction")))))
                                     (filter (lambda (b) (cell=? (Building-cell b) cell)) (World-buildings world)))
                                (map (lambda (d) (Label (string-append "Ore deposit · " (show (Deposit-reserve d)) " left")))
                                     (filter (lambda (d) (and (cell=? (Deposit-cell d) cell) (explored? world cell))) (World-deposits world))))))
                 ((None) (Nil))))))

    (: help-panel (-> World Panel))
    (define (help-panel world)
      (Panel (BottomRight)
             (list (Label (match (World-outcome world)
                            ((Won) "Victory! Start a new map to play again.")
                            ((Lost) "Defeat. Start a new map to play again.")
                            ((Playing) "WASD pans · wheel zooms · 1-3 choose a building · Esc cancels"))))))

    ;; ---- Frames ----

    (: view-game (-> Game F32 Frame))
    (define (view-game game alpha)
      (let ((world (Game-world game)))
        (Frame (game-camera game alpha) (rgb 16 20 28)
               (list (Batch 1 (i64->i32 (World-terrain-version world)) (lambda () (terrain-items world)))
                     (Batch 2 (i64->i32 (World-version world)) (lambda () (structure-items world)))
                     (Batch 3 (i64->i32 (+ (* (World-tick world) 128) (f32->i64 (* alpha 100.0)))) (lambda () (unit-items game alpha))))
               (list (status-panel world) (tool-panel game) (inspect-panel game) (help-panel world)))))

    ))
