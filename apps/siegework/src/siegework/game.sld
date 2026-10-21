;; The playable game around the simulation: camera, tools, pointer and
;; pause. `update-game` maps each input to a new Game.
(define-library (siegework game)
  (export
   Tool
   Select
   Place
   View
   View-heading
   Game
   Game-world
   Game-epoch
   Game-view
   Game-clock
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
   heading-angle
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
   (lofi math)
   (siegework grid)
   (siegework world)
   (siegework colony)
   (siegework simulation))
  (begin

    ;; ---- State ----

    (enum Tool
      (Select)
      (Place ((kind Kind))))

    ;; The camera looks down at 30 degrees on the point (x, z) of the ground,
    ;; from one of four quarter-turn headings, showing `scale` times 18
    ;; cells from the bottom of the screen to the top. `vx` and `vz` are its
    ;; motion per tick, used to draw smoothly between ticks. A turn eases
    ;; from `turned-from` over the three ticks of the game's clock after
    ;; `turned-at`.
    (struct View
      ((x F32)
       (z F32)
       (vx F32)
       (vz F32)
       (scale F32)
       (heading I64)
       (turned-from I64)
       (turned-at I64)))

    ;; `orders` is the journal of accepted orders, newest first; `selected`
    ;; is the cell orders apply to; `message` explains the last rejection.
    ;; `epoch` counts the games played since the page loaded, so a view of a
    ;; new game never reuses what was drawn for the last; `clock` counts
    ;; ticks of input, paused or not, for animating the view.
    (struct Game
      ((world World)
       (orders (List Entry))
       (epoch I64)
       (clock I64)
       (view View)
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
      (game-around (new-world (i32->i64 seed)) (Nil) 0 #f width height))

    (: game-around (-> World (List Entry) I64 Bool I32 I32 Game))
    (define (game-around world orders epoch paused width height)
      (let ((hub (Hub-cell (World-hub world))))
        (Game world orders epoch 0 (View (i64->f32 (Cell-x hub)) (i64->f32 (Cell-y hub)) 0.0 0.0 1.0 0 0 -3) (Nil) (Select) (None) (None) paused
              "Place an extractor on the crystal near the hub." width height)))

    (: game-save (-> Game Save))
    (define (game-save game)
      (let ((world (Game-world game)))
        (Save (World-seed world) (World-tick world) (reverse (Game-orders game)) (Game-paused game))))

    ;; The host reports the screen's size after restoring.
    (: game-restore (-> Save Game))
    (define (game-restore save)
      (match (replay (Save-seed save) (Save-orders save) (Save-tick save))
        ((Pair world orders) (game-around world (reverse orders) 0 (Save-paused save) 0 0))))

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

    ;; The heading in quarter turns, eased between the last two.
    (: heading-angle (-> Game F32 F32))
    (define (heading-angle game alpha)
      (let* ((view (Game-view game)) (from (i64->f32 (View-turned-from view))) (to (i64->f32 (View-heading view)))
             (t (clamp (/ (+ (i64->f32 (- (Game-clock game) (View-turned-at view))) alpha) 3.0) 0.0 1.0)))
        (* 1.5707964 (+ from (* (- to from) (* t (* t (- 3.0 (* 2.0 t)))))))))

    ;; Equal horizontal offsets give a 2:1 diamond for each resting quarter
    ;; turn; the height, sqrt((18^2 + 18^2) / 3), gives 30 degrees.
    (: game-camera (-> Game F32 Camera))
    (define (game-camera game alpha)
      (let* ((view (Game-view game)) (angle (f32->f64 (heading-angle game alpha)))
             (c (f64->f32 (cos angle))) (s (f64->f32 (sin angle))) (k (View-scale view))
             (target (Vec3 (+ (View-x view) (* alpha (View-vx view))) 0.0 (+ (View-z view) (* alpha (View-vz view))))))
        (Camera (Vec3 (+ (Vec3-x target) (* 18.0 (* k (+ c s)))) (* k 14.696938) (+ (Vec3-z target) (* 18.0 (* k (- c s)))))
                target (Orthographic (* 18.0 k)))))

    (: held? (-> Game I32 Bool))
    (define (held? game key)
      (member? key (Game-held game)))

    (: held-axis (-> Game I32 I32 I32 I32 F32))
    (define (held-axis game more more-key less less-key)
      (- (if (or (held? game more) (held? game more-key)) 1.0 0.0) (if (or (held? game less) (held? game less-key)) 1.0 0.0)))

    ;; The held keys pan in screen directions: right along the screen's
    ;; right on the ground, up away from the camera. Speed grows with zoom,
    ;; so the map moves at a steady rate on screen.
    (: move-camera (-> Game Game))
    (define (move-camera game)
      (let* ((view (Game-view game)) (angle (f32->f64 (heading-angle game 0.0)))
             (c (f64->f32 (cos angle))) (s (f64->f32 (sin angle))) (speed (* 0.35 (View-scale view)))
             (right (* speed (held-axis game key-right 100 key-left 97))) (up (* speed (held-axis game key-up 119 key-down 115)))
             (limit (i64->f32 map-size)))
        (Game-view-set game (View (clamp (+ (View-x view) (View-vx view)) 0.0 limit) (clamp (+ (View-z view) (View-vz view)) 0.0 limit)
                                  (* 0.70710677 (- (* right (- c s)) (* up (+ c s)))) (* 0.70710677 (- (* (negate right) (+ c s)) (* up (- c s))))
                                  (View-scale view) (View-heading view) (View-turned-from view) (View-turned-at view)))))

    (: clamp (-> F32 F32 F32 F32))
    (define (clamp value low high)
      (max low (min high value)))

    ;; Starts a quarter turn from wherever the current one has eased to.
    (: turn (-> Game I64 Game))
    (define (turn game quarters)
      (let ((view (Game-view game)))
        (Game-view-set game (View-turned-at-set (View-turned-from-set (View-heading-set view (+ (View-heading view) quarters)) (View-heading view))
                                                (Game-clock game)))))

    (: zoom (-> Game F32 Game))
    (define (zoom game factor)
      (let ((view (Game-view game)))
        (Game-view-set game (View-scale-set view (clamp (* (View-scale view) factor) 0.4 6.0)))))

    (: home (-> Game Game))
    (define (home game)
      (let ((hub (Hub-cell (World-hub (Game-world game)))) (view (Game-view game)))
        (Game-view-set game (View-z-set (View-x-set view (i64->f32 (Cell-x hub))) (i64->f32 (Cell-y hub))))))

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
        ((6) (game-around (new-world (+ (remainder (* (World-seed (Game-world game)) 48271) 65521) 1)) (Nil) (+ (Game-epoch game) 1) #f
                          (Game-width game) (Game-height game)))
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
              ((= key 113) (turn game -1))
              ((= key 101) (turn game 1))
              ((= key 104) (home game))
              ((= key key-escape) (Game-selected-set (Game-tool-set game (Select)) (None)))
              (else game))))

    ;; ---- Updates ----

    (: update-game (-> Game Input Game))
    (define (update-game game input)
      (match input
        ((Tick) (let ((game (move-camera (Game-clock-set game (+ (Game-clock game) 1)))))
                  (if (Game-paused game) game (Game-world-set game (advance (Game-world game))))))
        ((KeyDown key) (key-press game key))
        ((KeyUp key) (Game-held-set game (filter (lambda (k) (not (= k key))) (Game-held game))))
        ((PointerMove x y) (Game-hover-set game (pick game x y)))
        ((PointerDown x y button)
         (let ((game (Game-hover-set game (pick game x y))))
           (if (= button 0) (click game) (Game-selected-set (Game-tool-set game (Select)) (None)))))
        ((PointerUp x y button) game)
        ((Wheel delta) (zoom game (+ 1.0 (* 0.1 (i32->f32 delta)))))
        ((Resize width height) (Game-height-set (Game-width-set game width) height))
        ((Press action) (press game action))))

    ))
