;; What the player sees: the map, buildings, wires and units as mesh
;; instances, and the HUD. Batches are versioned so the host redraws the
;; map only when it changes.
(define-library (siegework view)
  (export
   view-game)
  (import
   (lofi base)
   (lofi app)
   (lofi math)
   (siegework grid)
   (siegework terrain)
   (siegework world)
   (siegework colony)
   (siegework siege)
   (siegework game))
  (begin

    ;; ---- Placement ----

    (: cell-point (-> Cell F32 Vec3))
    (define (cell-point cell height)
      (Vec3 (i64->f32 (Cell-x cell)) height (i64->f32 (Cell-y cell))))

    (: block (-> Mesh Vec3 F32 F32 F32 I32 Item))
    (define (block mesh position width height depth color)
      (item mesh position (Vec3 width height depth) 0.0 color))

    ;; An enemy steps on multiples of its period, so between steps it is
    ;; drawn partway from its previous cell.
    (: enemy-point (-> Enemy I64 F32 F32 Vec3))
    (define (enemy-point enemy tick alpha height)
      (let* ((period (enemy-period (Enemy-behavior enemy)))
             (progress (min 1.0 (/ (+ (i64->f32 (remainder (+ tick (Enemy-id enemy)) period)) alpha) (i64->f32 period))))
             (from (cell-point (Enemy-previous enemy) height)) (to (cell-point (Enemy-cell enemy) height)))
        (Vec3 (+ (Vec3-x from) (* progress (- (Vec3-x to) (Vec3-x from))))
              height
              (+ (Vec3-z from) (* progress (- (Vec3-z to) (Vec3-z from)))))))

    ;; A thin bar from one point to another, rotated to face along it.
    (: beam (-> Vec3 Vec3 F32 I32 Item))
    (define (beam from to thickness color)
      (let ((dx (- (Vec3-x to) (Vec3-x from))) (dz (- (Vec3-z to) (Vec3-z from))))
        (item (Box) (Vec3 (/ (+ (Vec3-x from) (Vec3-x to)) 2.0) (Vec3-y from) (/ (+ (Vec3-z from) (Vec3-z to)) 2.0))
              (Vec3 (sqrt (+ (* dx dx) (* dz dz))) thickness thickness) (atan2-f32 (negate dz) dx) color)))

    (: atan2-f32 (-> F32 F32 F32))
    (define (atan2-f32 y x)
      (f64->f32 (atan2 (f32->f64 y) (f32->f64 x))))

    ;; ---- Map ----

    (: terrain-items (-> World (List Item)))
    (define (terrain-items world)
      (map (lambda (index)
             (let ((cell (index-cell index)))
               (cond ((not (explored? world cell)) (block (Tile) (cell-point cell 0.0) 1.0 0.05 1.0 (rgb 28 32 40)))
                     (else (match (ground-at (World-land world) cell)
                             ((Rock) (block (Box) (cell-point cell 0.0) 0.95 0.7 0.95 (rgb 105 100 96)))
                             ((Water) (block (Tile) (cell-point cell 0.0) 1.0 0.05 1.0 (rgb 54 126 238)))
                             ((Grass) (block (Tile) (cell-point cell 0.0) 1.0 0.1 1.0 (if (visible? world cell) (rgb 74 104 66) (rgb 52 74 50)))))))))
           (iota (* map-size map-size))))

    ;; ---- Structures ----

    ;; Unfinished sites are grey and unpowered buildings dark.
    (: building-items (-> World Building (List Item)))
    (define (building-items world building)
      (let* ((cell (Building-cell building)) (level (i64->f32 (Building-level building)))
             (shade (lambda (color) (cond ((not (built? building)) (rgb 120 120 130))
                                          ((powered? world (Building-id building)) color)
                                          (else (rgb 70 70 80))))))
        (match (Building-kind building)
          ((Extractor) (list (block (Prism) (cell-point cell 0.1) 0.8 (+ 0.3 (* 0.3 level)) 0.8 (shade (rgb 210 150 60)))))
          ((Pylon) (list (block (Box) (cell-point cell 0.1) 0.4 (+ 0.4 (* 0.7 level)) 0.4 (shade (rgb 80 190 180)))))
          ((Turret) (list (block (Prism) (cell-point cell 0.1) 0.9 0.5 0.9 (shade (rgb 160 70 70)))
                          (block (Sphere) (cell-point cell 0.6) (+ 0.4 (* 0.1 level)) 0.5 (+ 0.4 (* 0.1 level)) (shade (rgb 200 90 80))))))))

    (: hub-items (-> Hub (List Item)))
    (define (hub-items hub)
      (list (block (Box) (cell-point (Hub-cell hub) 0.1) 2.6 1.0 2.6 (rgb 70 120 200))
            (block (Pyramid) (cell-point (Hub-cell hub) 1.1) 2.6 0.6 2.6 (rgb 220 220 230))))

    (: wire-items (-> World (List Item)))
    (define (wire-items world)
      (map (lambda (wire) (beam (cell-point (Node-cell (Wire-from wire)) 0.9) (cell-point (Node-cell (Wire-to wire)) 0.9) 0.06
                                (if (and (powered? world (Node-id (Wire-from wire))) (powered? world (Node-id (Wire-to wire)))) (rgb 120 230 255) (rgb 90 90 100))))
           (Network-wires (World-network world))))

    (: crystal-items (-> World (List Item)))
    (define (crystal-items world)
      (map (lambda (crystal)
             (let ((size (+ 0.3 (* 0.0002 (i64->f32 (Crystal-reserve crystal))))))
               (block (Pyramid) (cell-point (Crystal-cell crystal) 0.1) size size size (rgb 187 109 244))))
           (filter (lambda (crystal) (and (explored? world (Crystal-cell crystal)) (> (Crystal-reserve crystal) 0)
                                          (match (nest-at world (Crystal-cell crystal)) ((Some nest) (= (Nest-health nest) 0)) ((None) #t))))
                   (World-crystals world))))

    (: nest-items (-> World (List Item)))
    (define (nest-items world)
      (map (lambda (nest)
             (let ((size (+ 0.6 (* 0.001 (i64->f32 (Nest-health nest))))))
               (block (Sphere) (cell-point (Nest-cell nest) 0.0) size size size (rgb 120 30 40))))
           (filter (lambda (nest) (and (> (Nest-health nest) 0) (explored? world (Nest-cell nest)))) (World-nests world))))

    (: structure-items (-> World (List Item)))
    (define (structure-items world)
      (concatenate (list (hub-items (World-hub world)) (concatenate (map (lambda (b) (building-items world b)) (World-buildings world)))
                         (wire-items world) (crystal-items world) (nest-items world))))

    ;; ---- Units ----

    (: unit-items (-> Game F32 (List Item)))
    (define (unit-items game alpha)
      (let ((world (Game-world game)))
        (append (map (lambda (enemy) (block (Pyramid) (enemy-point enemy (World-tick world) alpha 0.1) 0.5 0.6 0.5 (rgb 220 50 50)))
                     (filter (lambda (enemy) (visible? world (Enemy-cell enemy))) (World-enemies world)))
                (append (map (lambda (shot) (beam (cell-point (Shot-from shot) 0.7) (cell-point (Shot-to shot) 0.4) 0.08 (rgb 255 230 120))) (World-shots world))
                        (cursor-items game)))))

    (: cursor-items (-> Game (List Item)))
    (define (cursor-items game)
      (append (match (Game-hover game)
                ((Some cell) (list (block (Tile) (cell-point cell 0.12) 1.0 0.04 1.0 (match (Game-tool game) ((Place _) (rgb 120 240 120)) ((Select) (rgb 240 240 240))))))
                ((None) (Nil)))
              (match (Game-selected game)
                ((Some cell) (list (block (Tile) (cell-point cell 0.14) 0.6 0.04 0.6 (rgb 255 220 90))))
                ((None) (Nil)))))

    ;; ---- HUD ----

    (: status-panel (-> World Panel))
    (define (status-panel world)
      (Panel (TopLeft)
             (list (Label (string-append "Energy " (show (World-energy world))))
                   (Label (string-append "Hub " (show (Hub-health (World-hub world))) " · slots " (show (Hub-slots (World-hub world)))))
                   (Label (string-append "Nests " (show (length (filter (lambda (n) (> (Nest-health n) 0)) (World-nests world))))))
                   (Meter (string-append "Attack " (show (attack-number (World-tick world))) " in "
                                         (show (quotient (- (next-attack-tick (World-tick world)) (World-tick world)) 10)) "s")
                          (- 1.0 (/ (i64->f32 (- (next-attack-tick (World-tick world)) (World-tick world))) 450.0))))))

    (: tool-panel (-> Game Panel))
    (define (tool-panel game)
      (let ((tool-button (lambda (kind)
                           (Button (string-append (kind-name kind) " " (show (raise-cost kind 0))) (action-tool kind)
                                   (match (Game-tool game) ((Place selected) (= (action-tool selected) (action-tool kind))) ((Select) #f))))))
        (Panel (BottomLeft)
               (list (tool-button (Extractor)) (tool-button (Pylon)) (tool-button (Turret))
                     (Button "Upgrade" action-upgrade #f) (Button "Rush" action-rush #f) (Button "Cancel" action-cancel #f)
                     (Button "Scavenge" action-scavenge #f) (Button "Repair" action-repair #f)
                     (Button (if (Game-paused game) "Resume" "Pause") action-pause (Game-paused game))
                     (Button "New map" action-new-map #f)))))

    (: work-text (-> Work String))
    (define (work-text work)
      (string-append " · working " (show (quotient (* 100 (Work-progress work)) (Work-duration work))) "%"
                     (if (Work-rushed work) " (rushed)" "")))

    (: inspect-panel (-> Game Panel))
    (define (inspect-panel game)
      (let ((world (Game-world game)))
        (Panel (TopRight)
               (match (focus-cell game)
                 ((Some cell)
                  (Cons (Label (string-append "Cell " (show (Cell-x cell)) ", " (show (Cell-y cell))))
                        (append (if (hub-cell? (World-hub world) cell) (list (Label (hub-text (World-hub world)))) (Nil))
                                (append (map (lambda (b) (Label (building-text world b))) (filter (lambda (b) (cell=? (Building-cell b) cell)) (World-buildings world)))
                                        (map (lambda (c) (Label (string-append "Crystal · " (show (Crystal-reserve c)) " left")))
                                             (filter (lambda (c) (and (cell=? (Crystal-cell c) cell) (explored? world cell))) (World-crystals world)))))))
                 ((None) (Nil))))))

    (: hub-text (-> Hub String))
    (define (hub-text hub)
      (string-append "Hub · health " (show (Hub-health hub)) " · slots " (show (Hub-slots hub))
                     (match (Hub-work hub) ((Some work) (work-text work)) ((None) ""))))

    (: building-text (-> World Building String))
    (define (building-text world b)
      (string-append (kind-name (Building-kind b)) " " (show (Building-level b)) " · health " (show (Building-health b))
                     (if (powered? world (Building-id b)) "" (if (built? b) " · unpowered" ""))
                     (match (Building-work b) ((Some work) (work-text work)) ((None) ""))))

    (: help-panel (-> Game Panel))
    (define (help-panel game)
      (Panel (BottomRight)
             (list (Label (Game-message game))
                   (Label (match (World-outcome (Game-world game))
                            ((Won) "Victory! Start a new map to play again.")
                            ((Lost) "Defeat. Start a new map to play again.")
                            ((Resigned) "Resigned. Start a new map to play again.")
                            ((Playing) "WASD pans · wheel zooms · 1-3 build · U upgrade · R rush · C cancel · X scavenge"))))))

    ;; ---- Frames ----

    (: view-game (-> Game F32 Frame))
    (define (view-game game alpha)
      (let ((world (Game-world game)))
        (Frame (game-camera game alpha) (Light (Vec3 0.4 1.0 0.3) 0.6 0.4) (rgb 16 20 28) 1.0
               (list (Batch 1 (i64->i32 (World-explored-version world)) (Solid) (lambda () (terrain-items world)))
                     (Batch 2 (i64->i32 (World-structure-version world)) (Solid) (lambda () (structure-items world)))
                     (Batch 3 (i64->i32 (+ (* (World-tick world) 128) (f32->i64 (* alpha 100.0)))) (Solid) (lambda () (unit-items game alpha))))
               (list (status-panel world) (tool-panel game) (inspect-panel game) (help-panel game)))))

    ))
