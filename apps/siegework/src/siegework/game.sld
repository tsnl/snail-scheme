;; The playable game around the simulation: the camera, the selected cell
;; and the orders given there, dialogs, and the journal of orders that saves
;; the game. `update-game` maps each input to a new Game.
;;
;; As in the original, selection alone never orders anything: tapping a
;; cell selects it and the HUD offers what can be done there, and each
;; button names the cell it acts on, so a stale button cannot act on a newer
;; selection.
(define-library (siegework game)
  (export
   View
   Menu
   Closed
   Paused
   Restarting
   Resigning
   Results
   Game
   Save
   new-game
   game-save
   game-restore
   update-game
   paused?
   tick-milliseconds
   world-motion
   game-camera
   heading-angle
   Command
   Build-at
   Upgrade-at
   Rush-at
   Cancel-at
   Scavenge-at
   Repair-hub
   Toggle-rush
   Close-card
   Locate
   Home
   Turn
   Open-menu
   Resume
   Ask-restart
   Ask-resign
   Confirm-resign
   New-map
   Hand
   Show-results
   Inspect-map
   press-code)
  (import
   (snail core base)
   (snail shell wire)
   (snail shell app)
   (snail shell math)
   (siegework grid)
   (only (siegework terrain))
   (siegework world)
   (siegework colony)
   (siegework simulation))
  (begin

    ;; ---- State ----

    ;; The camera looks down at 30 degrees on the point (x, z) of the ground,
    ;; from one of four quarter-turn headings, showing `scale` times 18
    ;; cells from the bottom of the screen to the top. A turn eases from
    ;; `turned-from` over the `turn-milliseconds` of the game's clock after
    ;; `turned-at`.
    (record View
      ((x F32)
       (z F32)
       (scale F32)
       (heading I64)
       (turned-from I64)
       (turned-at I64))
      (deriving Serialize Deserialize))

    ;; The dialog over the map. The menu and its confirmations pause the
    ;; colony; the results appear when the game is decided.
    (enum Menu
      (Closed)
      (Paused)
      (Restarting)
      (Resigning)
      (Results))

    ;; `orders` is the journal of accepted orders, newest first. `epoch`
    ;; counts the games played since the page loaded, so a view of a new game
    ;; never reuses what was drawn for the last. Time arrives with each
    ;; display frame: `Clock` counts every millisecond, for animating the
    ;; controls; `shown` counts the milliseconds the world has been shown
    ;; running, for its decorations, however long it waits for its first
    ;; order; and `phase` counts those since the world's last tick, for
    ;; moving its things. Both stop while the world is paused or decided.
    ;; `preview` is the
    ;; building whose button the pointer is over; `rush` makes new buildings
    ;; rushed; `message` explains the last rejected order.
    (record Game
      ((world World)
       (orders (List Entry))
       (epoch I64)
       (clock I64)
       (shown I64)
       (phase I64)
       (view View)
       (held (List I32))
       (gestures Gestures)
       (hover (Option Cell))
       (selected (Option Cell))
       (preview (Option Kind))
       (rush Bool)
       (menu Menu)
       (left-handed Bool)
       (message String)
       (width I32)
       (height I32)))

    ;; A save is the colony's seed, the tick it reached and its journal,
    ;; oldest entry first, so restoring replays the game; and how it was
    ;; being played: paused, for which hand, and the view, so a reloaded
    ;; page or module looks where the player was looking.
    (record Save
      ((seed I64)
       (tick I64)
       (orders (List Entry))
       (paused Bool)
       (left-handed Bool)
       (view View))
      (deriving Serialize Deserialize))

    (define (new-game (seed I32) (width I32) (height I32)) (→ Game)
      (game-around (new-world (i32->i64 seed)) (Nil) 0 (Closed) #f width height))

    ;; A game opens looking at its starter crystal, the first place to
    ;; build, four cells from the hub.
    (define (game-around (world World)
                         (orders (List Entry))
                         (epoch I64)
                         (menu Menu)
                         (left-handed Bool)
                         (width I32)
                         (height I32))
      (→ Game)
      (let ((start (● (● world land) starter)))
        (new Game (world world)
             (orders orders)
             (epoch epoch)
             (clock 0)
             (shown 0)
             (phase 0)
             (view (new View (x (i64->f32 (● start x)))
                        (z (i64->f32 (● start y)))
                        (scale 1.0)
                        (heading 0)
                        (turned-from 0)
                        (turned-at (negate (turn-milliseconds)))))
             (held (Nil))
             (gestures (no-gestures))
             (hover (None))
             (selected (None))
             (preview (None))
             (rush #f)
             (menu menu) (left-handed left-handed) (message "") (width width) (height height))))

    ;; ---- Time ----

    ;; The world advances once for each tenth of a second that passes.
    (define (tick-milliseconds) (→ I64) 100)

    ;; The camera takes this long to turn a quarter.
    (define (turn-milliseconds) (→ I64) 300)

    ;; The world is still while a dialog pauses it or once it is decided.
    (define (still? (game Game)) (→ Bool)
      (or (paused? game) (not (playing? (● game world)))))

    ;; How far the world's things have moved through the current tick; a
    ;; still world holds the frame it stopped at.
    (define (world-motion (game Game)) (→ F32)
      (min 1.0 (/ (i64->f32 (● game phase)) (i64->f32 (tick-milliseconds)))))

    (define (paused? (game Game)) (→ Bool)
      (match (● game menu)
        ((Paused) #t)
        ((Restarting) #t)
        ((Resigning) #t)
        (_ #f)))

    ;; The clock restarts with the restored game, so a turn in progress is
    ;; saved as finished.
    (define (game-save (game Game)) (→ Save)
      (let ((world (● game world)) (view (● game view)))
        (new Save (seed (● world seed))
             (tick (● world tick))
             (orders (reverse (● game orders)))
             (paused (paused? game))
             (left-handed (● game left-handed))
             (view (view-turned-at-set (view-turned-from-set view (● view heading))
                                       (negate (turn-milliseconds)))))))

    ;; The host reports the screen's size after restoring.
    (define (game-restore (save Save)) (→ Game)
      (match (replay (● save seed) (● save orders) (● save tick))
        ((Pair world orders)
         (game-view-set (game-around world
                                     (reverse orders)
                                     0
                                     (if (● save paused) (Paused) (Closed))
                                     (● save left-handed)
                                     0
                                     0)
                        (● save view)))))

    ;; ---- Camera ----

    ;; The heading in quarter turns, eased between the last two.
    (define (heading-angle (game Game)) (→ F32)
      (let* ((view (● game view))
             (from (i64->f32 (● view turned-from)))
             (to (i64->f32 (● view heading)))
             (t (clamp (/ (i64->f32 (- (● game clock) (● view turned-at)))
                          (i64->f32 (turn-milliseconds)))
                       0.0
                       1.0)))
        (* 1.5707964 (+ from (* (- to from) (* t (* t (- 3.0 (* 2.0 t)))))))))

    ;; Equal horizontal offsets give a 2:1 diamond for each resting quarter
    ;; turn; the height, sqrt((18^2 + 18^2) / 3), gives 30 degrees.
    (define (game-camera (game Game)) (→ Camera)
      (let* ((view (● game view)) (angle (f32->f64 (heading-angle game)))
             (c (f64->f32 (cos angle)))
             (s (f64->f32 (sin angle)))
             (k (● view scale))
             (target (new Vec3 (x (● view x)) (y 0.0) (z (● view z)))))
        (new Camera (eye (new Vec3 (x (+ (● target x) (* 18.0 (* k (+ c s)))))
                              (y (* k 14.696938))
                              (z (+ (● target z) (* 18.0 (* k (- c s)))))))
             (target target) (projection (Orthographic (* 18.0 k))))))

    (define (clamp (value F32) (low F32) (high F32)) (→ F32)
      (max low (min high value)))

    ;; Moves the camera's target by `right` along the screen's right on the
    ;; ground and `up` away from the viewer, within the map.
    (define (shifted (game Game) (right F32) (up F32)) (→ View)
      (let* ((view (● game view)) (angle (f32->f64 (heading-angle game)))
             (c (f64->f32 (cos angle))) (s (f64->f32 (sin angle))) (limit (i64->f32 (map-size))))
        (view-z-set (view-x-set view
                                (clamp (+ (● view x)
                                          (* 0.70710677 (- (* right (- c s)) (* up (+ c s)))))
                                       0.0
                                       limit))
                    (clamp
                     (+ (● view z) (* 0.70710677 (- (* (negate right) (+ c s)) (* up (- c s)))))
                     0.0
                     limit))))

    (define (held? (game Game) (key I32)) (→ Bool)
      (member? key (● game held)))

    (define (held-axis (game Game) (more I32) (more-key I32) (less I32) (less-key I32)) (→ F32)
      (- (if (or (held? game more) (held? game more-key)) 1.0 0.0)
         (if (or (held? game less) (held? game less-key)) 1.0 0.0)))

    ;; Held keys pan in screen directions at the original's nine cells a
    ;; second at the starting zoom, faster farther out, so the map moves at
    ;; a steady rate on screen. Up the screen covers twice the ground, seen
    ;; at 30 degrees, as dragging does.
    (define (move-camera (game Game) (milliseconds I64)) (→ Game)
      (let ((speed (* (* 0.009 (● (● game view) scale)) (i64->f32 milliseconds))))
        (game-view-set game
                       (shifted game
                                (* speed (held-axis game (key-right) 100 (key-left) 97))
                                (* (* 2.0 speed) (held-axis game (key-up) 119 (key-down) 115))))))

    ;; Dragging moves the ground with the pointer: a pixel is 18 times the
    ;; zoom over the screen's height across, and twice that up the screen,
    ;; where the ground is seen at 30 degrees.
    (define (pan (game Game) (dx I32) (dy I32)) (→ Game)
      (let ((unit (/ (* 18.0 (● (● game view) scale)) (i32->f32 (max 1 (● game height))))))
        (game-view-set game
                       (shifted game
                                (* (negate unit) (i32->f32 dx))
                                (* (* 2.0 unit) (i32->f32 dy))))))

    ;; Starts a quarter turn from wherever the current one has eased to.
    (define (turn (game Game) (quarters I64)) (→ Game)
      (let ((view (● game view)))
        (game-view-set game
                       (view-turned-at-set (view-turned-from-set
                                            (view-heading-set view (+ (● view heading) quarters))
                                            (● view heading))
                                           (● game clock)))))

    (define (zoom (game Game) (factor F32)) (→ Game)
      (let ((view (● game view)))
        (game-view-set game (view-scale-set view (clamp (* (● view scale) factor) 0.4 6.0)))))

    (define (look-at (game Game) (cell Cell)) (→ Game)
      (let ((view (● game view)))
        (game-view-set game
                       (view-z-set (view-x-set view (i64->f32 (● cell x)))
                                   (i64->f32 (● cell y))))))

    ;; The cell under a pixel, if the pointer is over the map.
    (define (pick (game Game) (x I32) (y I32)) (→ (Option Cell))
      (match (ground-point (game-camera game) x y (● game width) (● game height))
        ((Some point)
         (let ((cell
                (new Cell (x (f32->i64 (round (● point x)))) (y (f32->i64 (round (● point z)))))))
           (if (in-bounds? cell) (Some cell) (None))))
        ((None) (None))))

    ;; ---- Commands ----

    ;; What the HUD's buttons and the keys ask for. Orders carry the cell
    ;; they act on.
    (enum Command
      (Build-at ((kind Kind) (cell Cell)))
      (Upgrade-at ((cell Cell)))
      (Rush-at ((cell Cell)))
      (Cancel-at ((cell Cell)))
      (Scavenge-at ((cell Cell)))
      (Repair-hub)
      (Toggle-rush)
      (Close-card)
      (Locate ((cell Cell)))
      (Home)
      (Turn ((quarters I64)))
      (Open-menu)
      (Resume)
      (Ask-restart)
      (Ask-resign)
      (Confirm-resign)
      (New-map)
      (Hand ((left Bool)))
      (Show-results)
      (Inspect-map))

    ;; A command as a button's action and argument: a cell travels as its
    ;; index.
    (define (press-code (command Command)) (→ (Pair I32 I32))
      (let ((at (lambda (action cell)
                  (new Pair (first action) (second (i64->i32 (cell-index cell)))))))
        (match command
          ((Build-at (Extractor) cell) (at 1 cell))
          ((Build-at (Pylon) cell) (at 2 cell))
          ((Build-at (Turret) cell) (at 3 cell))
          ((Upgrade-at cell) (at 4 cell))
          ((Rush-at cell) (at 5 cell))
          ((Cancel-at cell) (at 6 cell))
          ((Scavenge-at cell) (at 7 cell))
          ((Locate cell) (at 8 cell))
          ((Turn quarters) (new Pair (first 10) (second (i64->i32 quarters))))
          ((Hand left) (new Pair (first 11) (second (if left 1 0))))
          (_ (new Pair (first (+ 20 (plain-code command))) (second 0))))))

    (define (plain-code (command Command)) (→ I32)
      (match command
        ((Repair-hub) 0)
        ((Toggle-rush) 1)
        ((Close-card) 2)
        ((Home) 3)
        ((Open-menu) 4)
        ((Resume) 5)
        ((Ask-restart) 6)
        ((Ask-resign) 7)
        ((Confirm-resign) 8)
        ((New-map) 9)
        ((Show-results) 10)
        ((Inspect-map) 11)
        (_ 12)))

    ;; The command a button reported, if it names one. A cell must lie on
    ;; the map, so numbers from the host cannot name another place.
    (define (parse-press (action I32) (argument I32)) (→ (Option Command))
      (if (and (< 0 action) (< action 10) (not (on-map? argument)))
          (None)
          (parse-code action argument)))

    (define (on-map? (index I32)) (→ Bool)
      (and (<= 0 index) (< (i32->i64 index) (* (map-size) (map-size)))))

    (define (parse-code (action I32) (argument I32)) (→ (Option Command))
      (let ((cell (index-cell (i32->i64 argument))))
        (case action
          ((1) (Some (Build-at (Extractor) cell)))
          ((2) (Some (Build-at (Pylon) cell)))
          ((3) (Some (Build-at (Turret) cell)))
          ((4) (Some (Upgrade-at cell)))
          ((5) (Some (Rush-at cell)))
          ((6) (Some (Cancel-at cell)))
          ((7) (Some (Scavenge-at cell)))
          ((8) (Some (Locate cell)))
          ((10) (Some (Turn (i32->i64 argument))))
          ((11) (Some (Hand (= argument 1))))
          (else (find (lambda (command) (= (plain-code command) (- action 20)))
                      (list (Repair-hub)
                            (Toggle-rush)
                            (Close-card)
                            (Home)
                            (Open-menu)
                            (Resume)
                            (Ask-restart)
                            (Ask-resign)
                            (Confirm-resign)
                            (New-map)
                            (Show-results)
                            (Inspect-map)))))))

    ;; Gives an order to the world and journals it; a rejection is shown
    ;; instead.
    (define (order (game Game) (action Action)) (→ Game)
      (match (command (● game world) action)
        ((Ok (Pair world entry))
         (game-message-set
          (game-orders-set (game-world-set game world) (Cons entry (● game orders)))
          ""))
        ((Err rejection) (game-message-set game (rejection-text rejection)))))

    (define (perform (game Game) (command Command)) (→ Game)
      (match command
        ((Build-at kind cell) (order game (Build kind cell (● game rush))))
        ((Upgrade-at cell) (order game (Upgrade cell)))
        ((Rush-at cell) (order game (Rush cell)))
        ((Cancel-at cell) (order game (Cancel cell)))
        ((Scavenge-at cell) (order game (Scavenge cell)))
        ((Repair-hub) (order game (Repair)))
        ((Toggle-rush) (game-rush-set game (not (● game rush))))
        ((Close-card) (game-message-set (game-selected-set game (None)) ""))
        ((Locate cell) (game-selected-set (look-at game cell) (Some cell)))
        ((Home) (look-at game (● (● (● game world) hub) cell)))
        ((Turn quarters) (turn game quarters))
        (_ (perform-menu game command))))

    (define (perform-menu (game Game) (command Command)) (→ Game)
      (match command
        ((Open-menu) (game-menu-set game (if (playing? (● game world)) (Paused) (Results))))
        ((Resume) (game-menu-set game (Closed)))
        ((Ask-restart) (game-menu-set game (Restarting)))
        ((Ask-resign) (game-menu-set game (Resigning)))
        ((Confirm-resign) (game-menu-set (order game (Resign)) (Results)))
        ((New-map) (restart game))
        ((Hand left) (game-left-handed-set game left))
        ((Show-results) (game-menu-set game (Results)))
        ((Inspect-map) (game-menu-set game (Closed)))
        (_ game)))

    ;; A new map from a seed derived from this one, for the same hand.
    (define (restart (game Game)) (→ Game)
      (game-around (new-world (+ (remainder (* (● (● game world) seed) 48271) 65521) 1))
                   (Nil)
                   (+ (● game epoch) 1)
                   (Closed)
                   (● game left-handed) (● game width) (● game height)))

    ;; ---- Keys ----

    ;; On a selected cell, 1, 2 and 3 build a pylon, a turret and an
    ;; extractor, 4 rushes (the selected work, or else new buildings) and 5
    ;; closes; letters act on the selection too.
    (define (key-command (game Game) (key I32)) (→ (Option Command))
      (match (● game selected)
        ((Some cell)
         (case key
           ((49) (Some (Build-at (Pylon) cell)))
           ((50) (Some (Build-at (Turret) cell)))
           ((51) (Some (Build-at (Extractor) cell)))
           ((52) (Some (rush-key game cell)))
           ((53) (Some (Close-card)))
           ((117) (Some (Upgrade-at cell)))
           ((114) (Some (rush-key game cell)))
           ((99) (Some (Cancel-at cell)))
           ((120) (Some (Scavenge-at cell)))
           (else (view-command key))))
        ((None) (view-command key))))

    ;; Rushing acts on the selected work, or else makes new buildings rushed.
    (define (rush-key (game Game) (cell Cell)) (→ Command)
      (if (working? (● game world) cell) (Rush-at cell) (Toggle-rush)))

    (define (view-command (key I32)) (→ (Option Command))
      (case key
        ((102) (Some (Repair-hub)))
        ((104) (Some (Home)))
        ((113) (Some (Turn -1)))
        ((101) (Some (Turn 1)))
        ((112) (Some (Open-menu)))
        (else (None))))

    (define (working? (world World) (cell Cell)) (→ Bool)
      (if (hub-cell? (● world hub) cell)
          (match (● (● world hub) work) ((Some _) #t) ((None) #f))
          (match (building-at world cell)
            ((Some b) (match (● b work) ((Some _) #t) ((None) #f)))
            ((None) #f))))

    ;; Escape backs out one step: a confirmation to the menu, the menu or
    ;; the results to the map, then the selection.
    (define (escape (game Game)) (→ Game)
      (match (● game menu)
        ((Closed) (perform game (Close-card)))
        ((Restarting) (game-menu-set game (Paused)))
        ((Resigning) (game-menu-set game (Paused)))
        (_ (game-menu-set game (Closed)))))

    ;; A key is held until released, so held keys pan. One pressed with
    ;; Shift is only held: Shift with WASD or the arrows pans as the key
    ;; alone does, and Shift with any other key does nothing. While a
    ;; dialog is open only it and the pause key answer.
    (define (key-press (game Game) (key I32) (shift Bool)) (→ Game)
      (let ((game (game-held-set game
                                 (if (held? game key)
                                     (● game held)
                                     (Cons key (● game held))))))
        (cond (shift game)
              ((= key (key-escape)) (escape game))
              ((= key 112)
               (if (paused? game) (game-menu-set game (Closed)) (perform game (Open-menu))))
              ((match (● game menu) ((Closed) #f) (_ #t)) game)
              ((or (= key (key-enter)) (= key (key-space))) (game-selected-set game (● game hover)))
              (else (match (key-command game key)
                      ((Some command) (perform game command))
                      ((None) game))))))

    ;; ---- Updates ----

    ;; Time moves the clock and the camera and, unless the world is still,
    ;; what is shown of it. Once the world has started, its phase grows too,
    ;; and each whole tick of it advances the world, at most a few at once
    ;; after a long frame. The results open once when the game is decided.
    (define (pass (game Game) (milliseconds I64)) (→ Game)
      (let ((game
             (move-camera (game-clock-set game (+ (● game clock) milliseconds)) milliseconds)))
        (cond ((still? game) game)
              ((● (● game world) started)
               (catch-up (game-phase-set (game-shown-set game (+ (● game shown) milliseconds))
                                         (+ (● game phase) milliseconds))
                         3))
              (else (game-shown-set game (+ (● game shown) milliseconds))))))

    (define (catch-up (game Game) (allowed I64)) (→ Game)
      (cond ((< (● game phase) (tick-milliseconds)) game)
            ((or (= allowed 0) (still? game))
             (game-phase-set game (min (● game phase) (- (tick-milliseconds) 1))))
            (else
             (catch-up (advance-world (game-phase-set game (- (● game phase) (tick-milliseconds))))
                       (- allowed 1)))))

    (define (advance-world (game Game)) (→ Game)
      (let ((world (advance (● game world))))
        (game-world-set (if (and (playing? (● game world)) (not (playing? world)))
                            (game-menu-set game (Results))
                            game)
                        world)))

    ;; Hovering over a building's button previews it on the selected cell.
    (define (hover (game Game) (action I32) (argument I32)) (→ Game)
      (game-preview-set game
                        (match (parse-press action argument)
                          ((Some (Build-at kind _)) (Some kind))
                          (_ (None)))))

    (define (update-game (game Game) (input Input)) (→ Game)
      (match input
        ((Elapsed milliseconds) (pass game (i32->i64 milliseconds)))
        ((Key-down key shift) (key-press game key shift))
        ((Key-up key) (game-held-set game (filter (lambda (k) (not (= k key))) (● game held))))
        ((Wheel pixels) (zoom game (+ 1.0 (* 0.001 (i32->f32 pixels)))))
        ((Resize width height) (game-height-set (game-width-set game width) height))
        ((Press action argument)
         (match (parse-press action argument)
           ((Some command) (perform game command))
           ((None) game)))
        ((Hover action argument) (hover game action argument))
        (_ (match (recognize (● game gestures) input)
             ((Pair gestures meanings)
              (fold-left gesture (game-gestures-set game gestures) meanings))))))

    ;; Pointing hovers, a tap selects the cell beneath it, dragging pans and
    ;; pinching zooms. A tap with another button clears the selection.
    (define (gesture (game Game) (meaning Gesture)) (→ Game)
      (match meaning
        ((Point x y) (game-hover-set game (pick game x y)))
        ((Tap x y button) (let ((cell (pick game x y)))
                            (game-message-set (game-selected-set (game-hover-set game cell)
                                                                 (if (= button 0) cell (None)))
                                              "")))
        ((Drag dx dy) (pan game dx dy))
        ((Pinch ratio) (zoom game ratio))))

    ))
