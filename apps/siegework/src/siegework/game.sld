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
   BuildAt
   UpgradeAt
   RushAt
   CancelAt
   ScavengeAt
   RepairHub
   ToggleRush
   CloseCard
   Locate
   Home
   Turn
   OpenMenu
   Resume
   AskRestart
   AskResign
   ConfirmResign
   NewMap
   Hand
   ShowResults
   InspectMap
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
    (struct View
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
    ;; display frame: `clock` counts every millisecond, for animating the
    ;; controls; `shown` counts the milliseconds the world has been shown
    ;; running, for its decorations, however long it waits for its first
    ;; order; and `phase` counts those since the world's last tick, for
    ;; moving its things. Both stop while the world is paused or decided.
    ;; `preview` is the
    ;; building whose button the pointer is over; `rush` makes new buildings
    ;; rushed; `message` explains the last rejected order.
    (struct Game
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
    (struct Save
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
        (Game world
              orders
              epoch
              0
              0
              0
              (View (i64->f32 (● start x))
                    (i64->f32 (● start y))
                    1.0
                    0
                    0
                    (negate (turn-milliseconds)))
              (Nil)
              (no-gestures)
              (None)
              (None)
              (None)
              #f
              menu left-handed "" width height)))

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
        (Save (● world seed)
              (● world tick)
              (reverse (● game orders))
              (paused? game)
              (● game left-handed)
              (View-turned-at-set (View-turned-from-set view (● view heading))
                                  (negate (turn-milliseconds))))))

    ;; The host reports the screen's size after restoring.
    (define (game-restore (save Save)) (→ Game)
      (match (replay (● save seed) (● save orders) (● save tick))
        ((Pair world orders)
         (Game-view-set (game-around world
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
             (target (Vec3 (● view x) 0.0 (● view z))))
        (Camera (Vec3 (+ (● target x) (* 18.0 (* k (+ c s))))
                      (* k 14.696938)
                      (+ (● target z) (* 18.0 (* k (- c s)))))
                target (Orthographic (* 18.0 k)))))

    (define (clamp (value F32) (low F32) (high F32)) (→ F32)
      (max low (min high value)))

    ;; Moves the camera's target by `right` along the screen's right on the
    ;; ground and `up` away from the viewer, within the map.
    (define (shifted (game Game) (right F32) (up F32)) (→ View)
      (let* ((view (● game view)) (angle (f32->f64 (heading-angle game)))
             (c (f64->f32 (cos angle))) (s (f64->f32 (sin angle))) (limit (i64->f32 (map-size))))
        (View-z-set (View-x-set view
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
        (Game-view-set game
                       (shifted game
                                (* speed (held-axis game (key-right) 100 (key-left) 97))
                                (* (* 2.0 speed) (held-axis game (key-up) 119 (key-down) 115))))))

    ;; Dragging moves the ground with the pointer: a pixel is 18 times the
    ;; zoom over the screen's height across, and twice that up the screen,
    ;; where the ground is seen at 30 degrees.
    (define (pan (game Game) (dx I32) (dy I32)) (→ Game)
      (let ((unit (/ (* 18.0 (● (● game view) scale)) (i32->f32 (max 1 (● game height))))))
        (Game-view-set game
                       (shifted game
                                (* (negate unit) (i32->f32 dx))
                                (* (* 2.0 unit) (i32->f32 dy))))))

    ;; Starts a quarter turn from wherever the current one has eased to.
    (define (turn (game Game) (quarters I64)) (→ Game)
      (let ((view (● game view)))
        (Game-view-set game
                       (View-turned-at-set (View-turned-from-set
                                            (View-heading-set view (+ (● view heading) quarters))
                                            (● view heading))
                                           (● game clock)))))

    (define (zoom (game Game) (factor F32)) (→ Game)
      (let ((view (● game view)))
        (Game-view-set game (View-scale-set view (clamp (* (● view scale) factor) 0.4 6.0)))))

    (define (look-at (game Game) (cell Cell)) (→ Game)
      (let ((view (● game view)))
        (Game-view-set game
                       (View-z-set (View-x-set view (i64->f32 (● cell x)))
                                   (i64->f32 (● cell y))))))

    ;; The cell under a pixel, if the pointer is over the map.
    (define (pick (game Game) (x I32) (y I32)) (→ (Option Cell))
      (match (ground-point (game-camera game) x y (● game width) (● game height))
        ((Some point)
         (let ((cell (Cell (f32->i64 (round (● point x))) (f32->i64 (round (● point z))))))
           (if (in-bounds? cell) (Some cell) (None))))
        ((None) (None))))

    ;; ---- Commands ----

    ;; What the HUD's buttons and the keys ask for. Orders carry the cell
    ;; they act on.
    (enum Command
      (BuildAt ((kind Kind) (cell Cell)))
      (UpgradeAt ((cell Cell)))
      (RushAt ((cell Cell)))
      (CancelAt ((cell Cell)))
      (ScavengeAt ((cell Cell)))
      (RepairHub)
      (ToggleRush)
      (CloseCard)
      (Locate ((cell Cell)))
      (Home)
      (Turn ((quarters I64)))
      (OpenMenu)
      (Resume)
      (AskRestart)
      (AskResign)
      (ConfirmResign)
      (NewMap)
      (Hand ((left Bool)))
      (ShowResults)
      (InspectMap))

    ;; A command as a button's action and argument: a cell travels as its
    ;; index.
    (define (press-code (command Command)) (→ (Pair I32 I32))
      (let ((at (lambda (action cell) (Pair action (i64->i32 (cell-index cell))))))
        (match command
          ((BuildAt (Extractor) cell) (at 1 cell))
          ((BuildAt (Pylon) cell) (at 2 cell))
          ((BuildAt (Turret) cell) (at 3 cell))
          ((UpgradeAt cell) (at 4 cell))
          ((RushAt cell) (at 5 cell))
          ((CancelAt cell) (at 6 cell))
          ((ScavengeAt cell) (at 7 cell))
          ((Locate cell) (at 8 cell))
          ((Turn quarters) (Pair 10 (i64->i32 quarters)))
          ((Hand left) (Pair 11 (if left 1 0)))
          (_ (Pair (+ 20 (plain-code command)) 0)))))

    (define (plain-code (command Command)) (→ I32)
      (match command
        ((RepairHub) 0)
        ((ToggleRush) 1)
        ((CloseCard) 2)
        ((Home) 3)
        ((OpenMenu) 4)
        ((Resume) 5)
        ((AskRestart) 6)
        ((AskResign) 7)
        ((ConfirmResign) 8)
        ((NewMap) 9)
        ((ShowResults) 10)
        ((InspectMap) 11)
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
          ((1) (Some (BuildAt (Extractor) cell)))
          ((2) (Some (BuildAt (Pylon) cell)))
          ((3) (Some (BuildAt (Turret) cell)))
          ((4) (Some (UpgradeAt cell)))
          ((5) (Some (RushAt cell)))
          ((6) (Some (CancelAt cell)))
          ((7) (Some (ScavengeAt cell)))
          ((8) (Some (Locate cell)))
          ((10) (Some (Turn (i32->i64 argument))))
          ((11) (Some (Hand (= argument 1))))
          (else (find (lambda (command) (= (plain-code command) (- action 20)))
                      (list (RepairHub)
                            (ToggleRush)
                            (CloseCard)
                            (Home)
                            (OpenMenu)
                            (Resume)
                            (AskRestart)
                            (AskResign)
                            (ConfirmResign)
                            (NewMap)
                            (ShowResults)
                            (InspectMap)))))))

    ;; Gives an order to the world and journals it; a rejection is shown
    ;; instead.
    (define (order (game Game) (action Action)) (→ Game)
      (match (command (● game world) action)
        ((Ok (Pair world entry))
         (Game-message-set
          (Game-orders-set (Game-world-set game world) (Cons entry (● game orders)))
          ""))
        ((Err rejection) (Game-message-set game (rejection-text rejection)))))

    (define (perform (game Game) (command Command)) (→ Game)
      (match command
        ((BuildAt kind cell) (order game (Build kind cell (● game rush))))
        ((UpgradeAt cell) (order game (Upgrade cell)))
        ((RushAt cell) (order game (Rush cell)))
        ((CancelAt cell) (order game (Cancel cell)))
        ((ScavengeAt cell) (order game (Scavenge cell)))
        ((RepairHub) (order game (Repair)))
        ((ToggleRush) (Game-rush-set game (not (● game rush))))
        ((CloseCard) (Game-message-set (Game-selected-set game (None)) ""))
        ((Locate cell) (Game-selected-set (look-at game cell) (Some cell)))
        ((Home) (look-at game (● (● (● game world) hub) cell)))
        ((Turn quarters) (turn game quarters))
        (_ (perform-menu game command))))

    (define (perform-menu (game Game) (command Command)) (→ Game)
      (match command
        ((OpenMenu) (Game-menu-set game (if (playing? (● game world)) (Paused) (Results))))
        ((Resume) (Game-menu-set game (Closed)))
        ((AskRestart) (Game-menu-set game (Restarting)))
        ((AskResign) (Game-menu-set game (Resigning)))
        ((ConfirmResign) (Game-menu-set (order game (Resign)) (Results)))
        ((NewMap) (restart game))
        ((Hand left) (Game-left-handed-set game left))
        ((ShowResults) (Game-menu-set game (Results)))
        ((InspectMap) (Game-menu-set game (Closed)))
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
           ((49) (Some (BuildAt (Pylon) cell)))
           ((50) (Some (BuildAt (Turret) cell)))
           ((51) (Some (BuildAt (Extractor) cell)))
           ((52) (Some (rush-key game cell)))
           ((53) (Some (CloseCard)))
           ((117) (Some (UpgradeAt cell)))
           ((114) (Some (rush-key game cell)))
           ((99) (Some (CancelAt cell)))
           ((120) (Some (ScavengeAt cell)))
           (else (view-command key))))
        ((None) (view-command key))))

    ;; Rushing acts on the selected work, or else makes new buildings rushed.
    (define (rush-key (game Game) (cell Cell)) (→ Command)
      (if (working? (● game world) cell) (RushAt cell) (ToggleRush)))

    (define (view-command (key I32)) (→ (Option Command))
      (case key
        ((102) (Some (RepairHub)))
        ((104) (Some (Home)))
        ((113) (Some (Turn -1)))
        ((101) (Some (Turn 1)))
        ((112) (Some (OpenMenu)))
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
        ((Closed) (perform game (CloseCard)))
        ((Restarting) (Game-menu-set game (Paused)))
        ((Resigning) (Game-menu-set game (Paused)))
        (_ (Game-menu-set game (Closed)))))

    ;; A key is held until released, so held keys pan. One pressed with
    ;; Shift is only held: Shift with WASD or the arrows pans as the key
    ;; alone does, and Shift with any other key does nothing. While a
    ;; dialog is open only it and the pause key answer.
    (define (key-press (game Game) (key I32) (shift Bool)) (→ Game)
      (let ((game (Game-held-set game
                                 (if (held? game key)
                                     (● game held)
                                     (Cons key (● game held))))))
        (cond (shift game)
              ((= key (key-escape)) (escape game))
              ((= key 112)
               (if (paused? game) (Game-menu-set game (Closed)) (perform game (OpenMenu))))
              ((match (● game menu) ((Closed) #f) (_ #t)) game)
              ((or (= key (key-enter)) (= key (key-space))) (Game-selected-set game (● game hover)))
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
             (move-camera (Game-clock-set game (+ (● game clock) milliseconds)) milliseconds)))
        (cond ((still? game) game)
              ((● (● game world) started)
               (catch-up (Game-phase-set (Game-shown-set game (+ (● game shown) milliseconds))
                                         (+ (● game phase) milliseconds))
                         3))
              (else (Game-shown-set game (+ (● game shown) milliseconds))))))

    (define (catch-up (game Game) (allowed I64)) (→ Game)
      (cond ((< (● game phase) (tick-milliseconds)) game)
            ((or (= allowed 0) (still? game))
             (Game-phase-set game (min (● game phase) (- (tick-milliseconds) 1))))
            (else
             (catch-up (advance-world (Game-phase-set game (- (● game phase) (tick-milliseconds))))
                       (- allowed 1)))))

    (define (advance-world (game Game)) (→ Game)
      (let ((world (advance (● game world))))
        (Game-world-set (if (and (playing? (● game world)) (not (playing? world)))
                            (Game-menu-set game (Results))
                            game)
                        world)))

    ;; Hovering over a building's button previews it on the selected cell.
    (define (hover (game Game) (action I32) (argument I32)) (→ Game)
      (Game-preview-set game
                        (match (parse-press action argument)
                          ((Some (BuildAt kind _)) (Some kind))
                          (_ (None)))))

    (define (update-game (game Game) (input Input)) (→ Game)
      (match input
        ((Elapsed milliseconds) (pass game (i32->i64 milliseconds)))
        ((KeyDown key shift) (key-press game key shift))
        ((KeyUp key) (Game-held-set game (filter (lambda (k) (not (= k key))) (● game held))))
        ((Wheel pixels) (zoom game (+ 1.0 (* 0.001 (i32->f32 pixels)))))
        ((Resize width height) (Game-height-set (Game-width-set game width) height))
        ((Press action argument)
         (match (parse-press action argument)
           ((Some command) (perform game command))
           ((None) game)))
        ((Hover action argument) (hover game action argument))
        (_ (match (recognize (● game gestures) input)
             ((Pair gestures meanings)
              (fold-left gesture (Game-gestures-set game gestures) meanings))))))

    ;; Pointing hovers, a tap selects the cell beneath it, dragging pans and
    ;; pinching zooms. A tap with another button clears the selection.
    (define (gesture (game Game) (meaning Gesture)) (→ Game)
      (match meaning
        ((Point x y) (Game-hover-set game (pick game x y)))
        ((Tap x y button) (let ((cell (pick game x y)))
                            (Game-message-set (Game-selected-set (Game-hover-set game cell)
                                                                 (if (= button 0) cell (None)))
                                              "")))
        ((Drag dx dy) (pan game dx dy))
        ((Pinch ratio) (zoom game ratio))))

    ))
