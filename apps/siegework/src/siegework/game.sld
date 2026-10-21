;; The playable game around the simulation: camera, tools, pointer and
;; pause. `update-game` maps each input to a new Game.
(define-library (siegework game)
  (export
   Tool
   Select
   Place
   Viewpoint
   Game
   Game-world
   Game-tool
   Game-hover
   Game-selected
   Game-paused
   Game-message
   Save
   new-game
   game-save
   game-restore
   update-game
   game-camera
   focus-cell
   action-tool
   action-upgrade
   action-rush
   action-cancel
   action-scavenge
   action-repair
   action-pause
   action-new-map)
  (import
   (lofi base)
   (lofi wire)
   (lofi app)
   (siegework grid)
   (siegework world)
   (siegework colony)
   (siegework simulation))
  (begin

    ;; ---- State ----

    (enum Tool
      (Select)
      (Place ((kind Kind))))

    ;; The camera looks at (x, z) from `distance` away; `vx` and `vz` are its
    ;; motion per tick, used to draw smoothly between ticks.
    (struct Viewpoint
      ((x F32)
       (z F32)
       (distance F32)
       (vx F32)
       (vz F32)))

    ;; `orders` is the journal of accepted orders, newest first; `selected`
    ;; is the cell orders apply to; `message` explains the last rejection.
    (struct Game
      ((world World)
       (orders (List Entry))
       (viewpoint Viewpoint)
       (held (List I32))
       (tool Tool)
       (hover (Option Cell))
       (selected (Option Cell))
       (paused Bool)
       (message String)
       (width I32)
       (height I32)))

    ;; A save is the colony's seed, the tick it reached and its journal,
    ;; oldest entry first, so restoring replays the game. Whether it was
    ;; paused is kept too; the view and selection start afresh.
    (struct Save
      ((seed I64)
       (tick I64)
       (orders (List Entry))
       (paused Bool))
      (deriving Serialize Deserialize))

    (: new-game (-> I32 I32 I32 Game))
    (define (new-game seed width height)
      (game-around (new-world (i32->i64 seed)) (Nil) #f width height))

    (: game-around (-> World (List Entry) Bool I32 I32 Game))
    (define (game-around world orders paused width height)
      (let ((hub (Hub-cell (World-hub world))))
        (Game world orders (Viewpoint (i64->f32 (Cell-x hub)) (i64->f32 (Cell-y hub)) 26.0 0.0 0.0) (Nil) (Select) (None) (None) paused
              "Place an extractor on the crystal near the hub." width height)))

    (: game-save (-> Game Save))
    (define (game-save game)
      (let ((world (Game-world game)))
        (Save (World-seed world) (World-tick world) (reverse (Game-orders game)) (Game-paused game))))

    ;; The host reports the screen's size after restoring.
    (: game-restore (-> Save Game))
    (define (game-restore save)
      (match (replay (Save-seed save) (Save-orders save) (Save-tick save))
        ((Pair world orders) (game-around world (reverse orders) (Save-paused save) 0 0))))

    ;; HUD buttons report these actions; 1-3 choose a building tool.
    (: action-tool (-> Kind I32))
    (define (action-tool kind)
      (match kind
        ((Extractor) 1)
        ((Pylon) 2)
        ((Turret) 3)))

    (define action-upgrade 4)
    (define action-pause 5)
    (define action-new-map 6)
    (define action-rush 7)
    (define action-cancel 8)
    (define action-scavenge 9)
    (define action-repair 10)

    ;; The cell orders apply to: the selected one, else the one hovered.
    (: focus-cell (-> Game (Option Cell)))
    (define (focus-cell game)
      (match (Game-selected game)
        ((Some cell) (Some cell))
        ((None) (Game-hover game))))

    ;; ---- Camera ----

    (: game-camera (-> Game F32 Camera))
    (define (game-camera game alpha)
      (let* ((view (Game-viewpoint game))
             (x (+ (Viewpoint-x view) (* alpha (Viewpoint-vx view))))
             (z (+ (Viewpoint-z view) (* alpha (Viewpoint-vz view))))
             (distance (Viewpoint-distance view)))
        (Camera (Vec3 x (* 0.85 distance) (+ z (* 0.55 distance))) (Vec3 x 0.0 z))))

    (: held? (-> Game I32 Bool))
    (define (held? game key)
      (member? key (Game-held game)))

    ;; Panning speed grows with distance, so the map moves at a steady
    ;; on-screen rate.
    (: move-camera (-> Game Game))
    (define (move-camera game)
      (let* ((view (Game-viewpoint game)) (speed (* 0.02 (Viewpoint-distance view)))
             (dx (- (if (or (held? game key-right) (held? game 100)) speed 0.0) (if (or (held? game key-left) (held? game 97)) speed 0.0)))
             (dz (- (if (or (held? game key-down) (held? game 115)) speed 0.0) (if (or (held? game key-up) (held? game 119)) speed 0.0)))
             (limit (i64->f32 map-size)))
        (Game-viewpoint-set game (Viewpoint (clamp (+ (Viewpoint-x view) (Viewpoint-vx view)) 0.0 limit)
                                            (clamp (+ (Viewpoint-z view) (Viewpoint-vz view)) 0.0 limit)
                                            (Viewpoint-distance view) dx dz))))

    (: clamp (-> F32 F32 F32 F32))
    (define (clamp value low high)
      (max low (min high value)))

    ;; The cell under a pixel, if the pointer is over the map.
    (: pick (-> Game I32 I32 (Option Cell)))
    (define (pick game x y)
      (match (ground-point (game-camera game 0.0) x y (Game-width game) (Game-height game))
        ((Some point)
         (let ((cell (Cell (f32->i64 (round (Vec3-x point))) (f32->i64 (round (Vec3-z point))))))
           (if (in-bounds? cell) (Some cell) (None))))
        ((None) (None))))

    ;; ---- Commands ----

    ;; Gives an order to the world and journals it; a rejection is shown
    ;; instead.
    (: order (-> Game Action Game))
    (define (order game action)
      (match (command (Game-world game) action)
        ((Ok (Pair world entry)) (Game-message-set (Game-orders-set (Game-world-set game world) (Cons entry (Game-orders game))) ""))
        ((Err rejection) (Game-message-set game (rejection-text rejection)))))

    (: order-at (-> Game (-> Cell Action) Game))
    (define (order-at game action)
      (match (focus-cell game)
        ((Some cell) (order game (action cell)))
        ((None) game)))

    (: click (-> Game Game))
    (define (click game)
      (match (Game-tool game)
        ((Place kind)
         (match (Game-hover game)
           ((Some cell) (order game (Build kind cell #f)))
           ((None) game)))
        ((Select) (Game-selected-set game (Game-hover game)))))

    (: press (-> Game I32 Game))
    (define (press game action)
      (case action
        ((1) (Game-tool-set game (Place (Extractor))))
        ((2) (Game-tool-set game (Place (Pylon))))
        ((3) (Game-tool-set game (Place (Turret))))
        ((4) (order-at game (lambda (cell) (Upgrade cell))))
        ((5) (Game-paused-set game (not (Game-paused game))))
        ((6) (new-game (i64->i32 (+ (remainder (* (World-seed (Game-world game)) 48271) 65521) 1)) (Game-width game) (Game-height game)))
        ((7) (order-at game (lambda (cell) (Rush cell))))
        ((8) (order-at game (lambda (cell) (Cancel cell))))
        ((9) (order-at game (lambda (cell) (Scavenge cell))))
        ((10) (order game (Repair)))
        (else game)))

    (: key-press (-> Game I32 Game))
    (define (key-press game key)
      (let ((game (Game-held-set game (if (held? game key) (Game-held game) (Cons key (Game-held game))))))
        (cond ((= key 49) (press game 1))
              ((= key 50) (press game 2))
              ((= key 51) (press game 3))
              ((= key 117) (press game action-upgrade))
              ((= key 114) (press game action-rush))
              ((= key 99) (press game action-cancel))
              ((= key 120) (press game action-scavenge))
              ((= key 112) (press game action-pause))
              ((= key key-escape) (Game-selected-set (Game-tool-set game (Select)) (None)))
              (else game))))

    ;; ---- Updates ----

    (: update-game (-> Game Input Game))
    (define (update-game game input)
      (match input
        ((Tick) (let ((game (move-camera game)))
                  (if (Game-paused game) game (Game-world-set game (advance (Game-world game))))))
        ((KeyDown key) (key-press game key))
        ((KeyUp key) (Game-held-set game (filter (lambda (k) (not (= k key))) (Game-held game))))
        ((PointerMove x y) (Game-hover-set game (pick game x y)))
        ((PointerDown x y button)
         (let ((game (Game-hover-set game (pick game x y))))
           (if (= button 0) (click game) (Game-selected-set (Game-tool-set game (Select)) (None)))))
        ((PointerUp x y button) game)
        ((Wheel delta)
         (let ((view (Game-viewpoint game)))
           (Game-viewpoint-set game (Viewpoint-distance-set view (clamp (* (Viewpoint-distance view) (+ 1.0 (* 0.1 (i32->f32 delta)))) 8.0 90.0)))))
        ((Resize width height) (Game-height-set (Game-width-set game width) height))
        ((Press action) (press game action))))

    ))
