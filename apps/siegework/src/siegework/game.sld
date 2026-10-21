;; The playable game around the simulation: the camera, the selected cell
;; and the orders given there, dialogs, muted alerts and the journal of
;; orders that saves the game. `update-game` maps each input to a new Game.
;;
;; As in the original, selection alone never orders anything: tapping a
;; cell selects it and the HUD offers what can be done there, and each
;; button names the cell it acts on, so a stale button cannot act on a newer
;; selection.
(define-library (siegework game)
  (export
   View
   View-heading
   Menu
   Closed
   Paused
   Restarting
   Resigning
   Results
   Mute
   Mute-cell
   Mute-until
   Game
   Game-world
   Game-epoch
   Game-view
   Game-clock
   Game-phase
   Game-shown
   Game-hover
   Game-selected
   Game-preview
   Game-rush
   Game-menu
   Game-left-handed
   Game-mutes
   Game-message
   Game-width
   Game-height
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
   Silence
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
   press-code
   alert-muted?)
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

    ;; The camera looks down at 30 degrees on the point (x, z) of the ground,
    ;; from one of four quarter-turn headings, showing `scale` times 18
    ;; cells from the bottom of the screen to the top. A turn eases from
    ;; `turned-from` over the 300 milliseconds of the game's clock after
    ;; `turned-at`.
    (struct View
      ((x F32)
       (z F32)
       (scale F32)
       (heading I64)
       (turned-from I64)
       (turned-at I64)))

    ;; The dialog over the map. The menu and its confirmations pause the
    ;; colony; the results appear when the game is decided.
    (enum Menu
      (Closed)
      (Paused)
      (Restarting)
      (Resigning)
      (Results))

    ;; Alerts near `cell` stay hidden until the world reaches `until`.
    (struct Mute
      ((cell Cell)
       (until I64)))

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
       (mutes (List Mute))
       (message String)
       (width I32)
       (height I32)))

    ;; A save is the colony's seed, the tick it reached and its journal,
    ;; oldest entry first, so restoring replays the game; and how it was
    ;; being played: paused, and for which hand.
    (struct Save
      ((seed I64)
       (tick I64)
       (orders (List Entry))
       (paused Bool)
       (left-handed Bool))
      (deriving Serialize Deserialize))

    (: new-game (-> I32 I32 I32 Game))
    (define (new-game seed width height)
      (game-around (new-world (i32->i64 seed)) (Nil) 0 (Closed) #f width height))

    (: game-around (-> World (List Entry) I64 Menu Bool I32 I32 Game))
    (define (game-around world orders epoch menu left-handed width height)
      (let ((hub (Hub-cell (World-hub world))))
        (Game world orders epoch 0 0 0 (View (i64->f32 (Cell-x hub)) (i64->f32 (Cell-y hub)) 1.0 0 0 -300) (Nil) no-gestures (None) (None) (None) #f
              menu left-handed (Nil) "" width height)))

    ;; ---- Time ----

    ;; The world advances once for each tenth of a second that passes.
    (: tick-milliseconds I64)
    (define tick-milliseconds 100)

    ;; The world is still while a dialog pauses it or once it is decided.
    (: still? (-> Game Bool))
    (define (still? game)
      (or (paused? game) (not (playing? (Game-world game)))))

    ;; How far the world's things have moved through the current tick; a
    ;; still world holds the frame it stopped at.
    (: world-motion (-> Game F32))
    (define (world-motion game)
      (min 1.0 (/ (i64->f32 (Game-phase game)) (i64->f32 tick-milliseconds))))

    (: paused? (-> Game Bool))
    (define (paused? game)
      (match (Game-menu game)
        ((Paused) #t)
        ((Restarting) #t)
        ((Resigning) #t)
        (_ #f)))

    (: game-save (-> Game Save))
    (define (game-save game)
      (let ((world (Game-world game)))
        (Save (World-seed world) (World-tick world) (reverse (Game-orders game)) (paused? game) (Game-left-handed game))))

    ;; The host reports the screen's size after restoring.
    (: game-restore (-> Save Game))
    (define (game-restore save)
      (match (replay (Save-seed save) (Save-orders save) (Save-tick save))
        ((Pair world orders) (game-around world (reverse orders) 0 (if (Save-paused save) (Paused) (Closed)) (Save-left-handed save) 0 0))))

    ;; ---- Camera ----

    ;; The heading in quarter turns, eased between the last two.
    (: heading-angle (-> Game F32))
    (define (heading-angle game)
      (let* ((view (Game-view game)) (from (i64->f32 (View-turned-from view))) (to (i64->f32 (View-heading view)))
             (t (clamp (/ (i64->f32 (- (Game-clock game) (View-turned-at view))) 300.0) 0.0 1.0)))
        (* 1.5707964 (+ from (* (- to from) (* t (* t (- 3.0 (* 2.0 t)))))))))

    ;; Equal horizontal offsets give a 2:1 diamond for each resting quarter
    ;; turn; the height, sqrt((18^2 + 18^2) / 3), gives 30 degrees.
    (: game-camera (-> Game Camera))
    (define (game-camera game)
      (let* ((view (Game-view game)) (angle (f32->f64 (heading-angle game)))
             (c (f64->f32 (cos angle))) (s (f64->f32 (sin angle))) (k (View-scale view)) (target (Vec3 (View-x view) 0.0 (View-z view))))
        (Camera (Vec3 (+ (Vec3-x target) (* 18.0 (* k (+ c s)))) (* k 14.696938) (+ (Vec3-z target) (* 18.0 (* k (- c s)))))
                target (Orthographic (* 18.0 k)))))

    (: clamp (-> F32 F32 F32 F32))
    (define (clamp value low high)
      (max low (min high value)))

    ;; Moves the camera's target by `right` along the screen's right on the
    ;; ground and `up` away from the viewer, within the map.
    (: shifted (-> Game F32 F32 View))
    (define (shifted game right up)
      (let* ((view (Game-view game)) (angle (f32->f64 (heading-angle game)))
             (c (f64->f32 (cos angle))) (s (f64->f32 (sin angle))) (limit (i64->f32 map-size)))
        (View-z-set (View-x-set view (clamp (+ (View-x view) (* 0.70710677 (- (* right (- c s)) (* up (+ c s))))) 0.0 limit))
                    (clamp (+ (View-z view) (* 0.70710677 (- (* (negate right) (+ c s)) (* up (- c s))))) 0.0 limit))))

    (: held? (-> Game I32 Bool))
    (define (held? game key)
      (member? key (Game-held game)))

    (: held-axis (-> Game I32 I32 I32 I32 F32))
    (define (held-axis game more more-key less less-key)
      (- (if (or (held? game more) (held? game more-key)) 1.0 0.0) (if (or (held? game less) (held? game less-key)) 1.0 0.0)))

    ;; Held keys pan in screen directions at the original's nine cells a
    ;; second at the starting zoom, faster farther out, so the map moves at
    ;; a steady rate on screen. Up the screen covers twice the ground, seen
    ;; at 30 degrees, as dragging does.
    (: move-camera (-> Game I64 Game))
    (define (move-camera game milliseconds)
      (let ((speed (* (* 0.009 (View-scale (Game-view game))) (i64->f32 milliseconds))))
        (Game-view-set game (shifted game (* speed (held-axis game key-right 100 key-left 97)) (* (* 2.0 speed) (held-axis game key-up 119 key-down 115))))))

    ;; Dragging moves the ground with the pointer: a pixel is 18 times the
    ;; zoom over the screen's height across, and twice that up the screen,
    ;; where the ground is seen at 30 degrees.
    (: pan (-> Game I32 I32 Game))
    (define (pan game dx dy)
      (let ((unit (/ (* 18.0 (View-scale (Game-view game))) (i32->f32 (max 1 (Game-height game))))))
        (Game-view-set game (shifted game (* (negate unit) (i32->f32 dx)) (* (* 2.0 unit) (i32->f32 dy))))))

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

    (: look-at (-> Game Cell Game))
    (define (look-at game cell)
      (let ((view (Game-view game)))
        (Game-view-set game (View-z-set (View-x-set view (i64->f32 (Cell-x cell))) (i64->f32 (Cell-y cell))))))

    ;; The cell under a pixel, if the pointer is over the map.
    (: pick (-> Game I32 I32 (Option Cell)))
    (define (pick game x y)
      (match (ground-point (game-camera game) x y (Game-width game) (Game-height game))
        ((Some point)
         (let ((cell (Cell (f32->i64 (round (Vec3-x point))) (f32->i64 (round (Vec3-z point))))))
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
      (Silence ((cell Cell)))
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
    (: press-code (-> Command (Pair I32 I32)))
    (define (press-code command)
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
          ((Silence cell) (at 9 cell))
          ((Turn quarters) (Pair 10 (i64->i32 quarters)))
          ((Hand left) (Pair 11 (if left 1 0)))
          (_ (Pair (+ 20 (plain-code command)) 0)))))

    (: plain-code (-> Command I32))
    (define (plain-code command)
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
    (: parse-press (-> I32 I32 (Option Command)))
    (define (parse-press action argument)
      (if (and (< 0 action) (< action 10) (not (on-map? argument))) (None) (parse-code action argument)))

    (: on-map? (-> I32 Bool))
    (define (on-map? index)
      (and (<= 0 index) (< (i32->i64 index) (* map-size map-size))))

    (: parse-code (-> I32 I32 (Option Command)))
    (define (parse-code action argument)
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
          ((9) (Some (Silence cell)))
          ((10) (Some (Turn (i32->i64 argument))))
          ((11) (Some (Hand (= argument 1))))
          (else (find (lambda (command) (= (plain-code command) (- action 20)))
                      (list (RepairHub) (ToggleRush) (CloseCard) (Home) (OpenMenu) (Resume) (AskRestart) (AskResign) (ConfirmResign) (NewMap) (ShowResults) (InspectMap)))))))

    ;; Gives an order to the world and journals it; a rejection is shown
    ;; instead.
    (: order (-> Game Action Game))
    (define (order game action)
      (match (command (Game-world game) action)
        ((Ok (Pair world entry)) (Game-message-set (Game-orders-set (Game-world-set game world) (Cons entry (Game-orders game))) ""))
        ((Err rejection) (Game-message-set game (rejection-text rejection)))))

    (: perform (-> Game Command Game))
    (define (perform game command)
      (match command
        ((BuildAt kind cell) (order game (Build kind cell (Game-rush game))))
        ((UpgradeAt cell) (order game (Upgrade cell)))
        ((RushAt cell) (order game (Rush cell)))
        ((CancelAt cell) (order game (Cancel cell)))
        ((ScavengeAt cell) (order game (Scavenge cell)))
        ((RepairHub) (order game (Repair)))
        ((ToggleRush) (Game-rush-set game (not (Game-rush game))))
        ((CloseCard) (Game-message-set (Game-selected-set game (None)) ""))
        ((Locate cell) (Game-selected-set (look-at game cell) (Some cell)))
        ((Silence cell) (silence game cell))
        ((Home) (look-at game (Hub-cell (World-hub (Game-world game)))))
        ((Turn quarters) (turn game quarters))
        (_ (perform-menu game command))))

    (: perform-menu (-> Game Command Game))
    (define (perform-menu game command)
      (match command
        ((OpenMenu) (Game-menu-set game (if (playing? (Game-world game)) (Paused) (Results))))
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
    (: restart (-> Game Game))
    (define (restart game)
      (game-around (new-world (+ (remainder (* (World-seed (Game-world game)) 48271) 65521) 1)) (Nil) (+ (Game-epoch game) 1) (Closed)
                   (Game-left-handed game) (Game-width game) (Game-height game)))

    ;; ---- Alerts ----

    ;; Silencing an area hides its alerts for eight seconds; the four most
    ;; recent silences are kept.
    (: silence (-> Game Cell Game))
    (define (silence game cell)
      (Game-mutes-set game (take (Cons (Mute cell (+ (World-tick (Game-world game)) 80)) (Game-mutes game)) 4)))

    (: alert-muted? (-> Game Alert Bool))
    (define (alert-muted? game alert)
      (any? (lambda (mute) (and (within? (Alert-cell alert) (Mute-cell mute) 4) (< (World-tick (Game-world game)) (Mute-until mute)))) (Game-mutes game)))

    ;; ---- Keys ----

    ;; On a selected cell, 1, 2 and 3 build a pylon, a turret and an
    ;; extractor, 4 rushes (the selected work, or else new buildings) and 5
    ;; closes; letters act on the selection too.
    (: key-command (-> Game I32 (Option Command)))
    (define (key-command game key)
      (match (Game-selected game)
        ((Some cell)
         (case key
           ((49) (Some (BuildAt (Pylon) cell)))
           ((50) (Some (BuildAt (Turret) cell)))
           ((51) (Some (BuildAt (Extractor) cell)))
           ((52) (Some (rush-key game cell)))
           ((53) (Some (CloseCard)))
           ((117) (Some (UpgradeAt cell)))
           ((99) (Some (CancelAt cell)))
           ((120) (Some (ScavengeAt cell)))
           (else (view-command key))))
        ((None) (view-command key))))

    ;; Rushing acts on the selected work, or else makes new buildings rushed.
    (: rush-key (-> Game Cell Command))
    (define (rush-key game cell)
      (if (working? (Game-world game) cell) (RushAt cell) (ToggleRush)))

    (: view-command (-> I32 (Option Command)))
    (define (view-command key)
      (case key
        ((102) (Some (RepairHub)))
        ((104) (Some (Home)))
        ((113) (Some (Turn -1)))
        ((101) (Some (Turn 1)))
        ((112) (Some (OpenMenu)))
        (else (None))))

    (: working? (-> World Cell Bool))
    (define (working? world cell)
      (if (hub-cell? (World-hub world) cell)
          (match (Hub-work (World-hub world)) ((Some _) #t) ((None) #f))
          (match (building-at world cell) ((Some b) (match (Building-work b) ((Some _) #t) ((None) #f))) ((None) #f))))

    ;; Escape backs out one step: a confirmation to the menu, the menu or
    ;; the results to the map, then the selection.
    (: escape (-> Game Game))
    (define (escape game)
      (match (Game-menu game)
        ((Closed) (perform game (CloseCard)))
        ((Restarting) (Game-menu-set game (Paused)))
        ((Resigning) (Game-menu-set game (Paused)))
        (_ (Game-menu-set game (Closed)))))

    ;; While a dialog is open only it and the pause key answer.
    (: key-press (-> Game I32 Game))
    (define (key-press game key)
      (let ((game (Game-held-set game (if (held? game key) (Game-held game) (Cons key (Game-held game))))))
        (cond ((= key key-escape) (escape game))
              ((= key 112) (if (paused? game) (Game-menu-set game (Closed)) (perform game (OpenMenu))))
              ((match (Game-menu game) ((Closed) #f) (_ #t)) game)
              ((or (= key key-enter) (= key key-space)) (Game-selected-set game (Game-hover game)))
              (else (match (key-command game key) ((Some command) (perform game command)) ((None) game))))))

    ;; ---- Updates ----

    ;; Time moves the clock and the camera and, unless the world is still,
    ;; what is shown of it. Once the world has started, its phase grows too,
    ;; and each whole tick of it advances the world, at most a few at once
    ;; after a long frame. The results open once when the game is decided.
    (: pass (-> Game I64 Game))
    (define (pass game milliseconds)
      (let ((game (move-camera (Game-clock-set game (+ (Game-clock game) milliseconds)) milliseconds)))
        (cond ((still? game) game)
              ((World-started (Game-world game))
               (catch-up (Game-phase-set (Game-shown-set game (+ (Game-shown game) milliseconds)) (+ (Game-phase game) milliseconds)) 3))
              (else (Game-shown-set game (+ (Game-shown game) milliseconds))))))

    (: catch-up (-> Game I64 Game))
    (define (catch-up game allowed)
      (cond ((< (Game-phase game) tick-milliseconds) game)
            ((or (= allowed 0) (still? game)) (Game-phase-set game (min (Game-phase game) (- tick-milliseconds 1))))
            (else (catch-up (advance-world (Game-phase-set game (- (Game-phase game) tick-milliseconds))) (- allowed 1)))))

    (: advance-world (-> Game Game))
    (define (advance-world game)
      (let ((world (advance (Game-world game))))
        (Game-world-set (if (and (playing? (Game-world game)) (not (playing? world))) (Game-menu-set game (Results)) game) world)))

    ;; Hovering over a building's button previews it on the selected cell.
    (: hover (-> Game I32 I32 Game))
    (define (hover game action argument)
      (Game-preview-set game (match (parse-press action argument) ((Some (BuildAt kind _)) (Some kind)) (_ (None)))))

    (: update-game (-> Game Input Game))
    (define (update-game game input)
      (match input
        ((Elapsed milliseconds) (pass game (i32->i64 milliseconds)))
        ((KeyDown key) (key-press game key))
        ((KeyUp key) (Game-held-set game (filter (lambda (k) (not (= k key))) (Game-held game))))
        ((Wheel pixels) (zoom game (+ 1.0 (* 0.001 (i32->f32 pixels)))))
        ((Resize width height) (Game-height-set (Game-width-set game width) height))
        ((Press action argument) (match (parse-press action argument) ((Some command) (perform game command)) ((None) game)))
        ((Hover action argument) (hover game action argument))
        (_ (match (recognize (Game-gestures game) input)
             ((Pair gestures meanings) (fold-left gesture (Game-gestures-set game gestures) meanings))))))

    ;; Pointing hovers, a tap selects the cell beneath it, dragging pans and
    ;; pinching zooms. A tap with another button clears the selection.
    (: gesture (-> Game Gesture Game))
    (define (gesture game meaning)
      (match meaning
        ((Point x y) (Game-hover-set game (pick game x y)))
        ((Tap x y button) (let ((cell (pick game x y)))
                            (Game-message-set (Game-selected-set (Game-hover-set game cell) (if (= button 0) cell (None))) "")))
        ((Drag dx dy) (pan game dx dy))
        ((Pinch ratio) (zoom game ratio))))

    ))
