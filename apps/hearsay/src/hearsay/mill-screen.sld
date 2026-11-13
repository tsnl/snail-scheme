;; The rumor mill in the browser: the town as a 2D map of its people, each a
;; figure on a base in their audience's color, with pips over their head
;; for what they believe. Around it, the HUD says what to do next, how the
;; goal stands, who the chosen person is and what they have heard, and
;; what each audience believes, with a button for each move that says why
;; when it cannot be made. A guide explains the game the first time.
(define-library (hearsay mill-screen)
  (export
   MillScreen
   new-mill-screen
   update-mill-screen
   view-mill-screen
   mill-screen-hud)
  (import
   (snail core base)
   (snail shell wire)
   (snail shell app)
   (snail shell math)
   (snail shell sprite)
   (only (lpc layout) Stand Stroll walk-book)
   (lpc wardrobe)
   (hearsay mill)
   (hearsay cast)
   (hearsay hud))
  (begin

    ;; ---- State ----

    ;; `message` is what the last shift did, a line each, or why it could
    ;; not be taken. `fresh` lists who heard something new in it. The
    ;; forecast takes simulating several shifts, so it is worked out once
    ;; per shift rather than every frame. `version` changes with every
    ;; shift, so the host redraws the town only then. `guide` is the guide's
    ;; open page, if any.
    (struct MillScreen
      ((mill Mill)
       (forecast (List String))
       (selected (Option I64))
       (hover (Option I64))
       (message (List String))
       (fresh (List I64))
       (version I64)
       (guide (Option I64))
       (width I32)
       (height I32))
      (deriving Serialize Deserialize))

    ;; `version` must differ from any town the host has drawn before.
    (define (new-mill-screen (scenario Scenario) (version I64) (width I32) (height I32))
      (→ MillScreen)
      (let ((mill (new-mill scenario)))
        (MillScreen mill (forecast mill) (None) (None) (Nil) (Nil) version (None) width height)))

    ;; ---- Layout ----

    ;; The town is a map seen straight down by an orthographic camera,
    ;; scaled to fill the middle of the screen between the HUD's columns.
    ;; Its extent on the ground, with room above the top ring for heads and
    ;; pips:
    (define town-left -10.2)
    (define town-right 10.2)
    (define town-top -11.4)
    (define town-bottom 6.0)

    ;; The pixels each HUD column takes from a side of the screen: a panel's
    ;; 300 and its margin, or a fifth of a narrow screen, where they overlap
    ;; the map rather than shrink it to nothing.
    (define (hud-column (width F32)) (→ F32)
      (if (< width 800.0) (* 0.2 width) 318.0))

    (define (camera-of (screen MillScreen)) (→ Camera)
      (let* ((width (max 1.0 (i32->f32 (● screen width))))
             (height (max 1.0 (i32->f32 (● screen height))))
             (across (max 120.0 (- width (* 2.0 (hud-column width)))))
             (down (max 120.0 (- height 24.0)))
             (pixels-per-unit
              (min (/ across (- town-right town-left)) (/ down (- town-bottom town-top))))
             (x (/ (+ town-left town-right) 2.0)) (z (/ (+ town-top town-bottom) 2.0)))
        (Camera (Vec3 x 40.0 z) (Vec3 x 0.0 z) (Orthographic (/ height pixels-per-unit)))))

    (define sunlight (Light (Vec3 0.0 1.0 0.0) 0.0 1.0))

    ;; Audiences sit on a triangle, each person on a ring of radius 2.8.
    (define (person-point (person I64)) (→ Vec3)
      (let* ((audience (audience-of person))
             (cx (list-ref (list -6.3 6.3 0.0) audience))
             (cz (list-ref (list 2.4 2.4 -6.2) audience))
             (angle (* (i64->f64 (remainder person 8)) (/ pi 4.0))))
        (Vec3 (f64->f32 (+ cx (* 2.8 (cos angle)))) 0.0 (f64->f32 (+ cz (* 2.8 (sin angle)))))))

    ;; A figure's cell is `figure-size` units square. Its feet stand at the
    ;; middle of its base, a little above the cell's bottom edge, and its
    ;; body fills about the middle half of the cell's width.
    (define figure-size 2.0)
    (define feet-offset 0.35)

    ;; Everyone faces the viewer, down the map.
    (define toward-viewer (Vec3 0.0 0.0 1.0))

    ;; The person whose figure or base is under the pointer, the one nearest
    ;; the bottom of the map when figures overlap.
    (define (pick (screen MillScreen) (x I32) (y I32)) (→ (Option I64))
      (match (ground-point (camera-of screen)
                           x
                           y
                           (● screen width)
                           (● screen height))
        ((Some point)
         (fold-left (lambda (best person)
                      (if (and (over? point person)
                               (match best
                                 ((Some other)
                                  (> (● (person-point person) z) (● (person-point other) z)))
                                 ((None) #t)))
                          (Some person)
                          best))
                    (None)
                    (iota person-count)))
        ((None) (None))))

    (define (over? (point Vec3) (person I64)) (→ Bool)
      (let* ((at (person-point person))
             (across (abs (- (● point x) (● at x))))
             (down (- (● point z) (● at z))))
        (and (< across (* 0.32 figure-size)) (< down 0.7) (> down (negate (* 0.85 figure-size))))))

    ;; ---- Actions ----

    ;; Buttons 1 to 5 are the deeds in order, 6 pays, 7 and 8 lie, 9 lies
    ;; low, 10 restarts, and 100 + p chooses person p.
    (define action-deed 1)
    (define action-pay 6)
    (define action-lie-reliable 7)
    (define action-lie-harmless 8)
    (define action-wait 9)
    (define action-restart 10)
    (define action-choose 100)

    (define (person-action (action I32) (person I64)) (→ Action)
      (cond ((< action action-pay) (Do (list-ref deeds (i32->i64 (- action action-deed))) person))
            ((= action action-pay) (Pay person))
            ((= action action-lie-reliable) (Mislead (Reliable) person))
            (else (Mislead (Harmless) person))))

    ;; Takes the shift, or shows why it cannot be taken.
    (define (act (screen MillScreen) (action Action)) (→ MillScreen)
      (let ((before (● screen mill)))
        (match (take-shift before action)
          ((Ok result) (record-shift screen before (● result first) (● result second)))
          ((Err message) (MillScreen-message-set screen (list message))))))

    ;; Remembers the new state, what it said, and who heard something new.
    (define (record-shift (screen MillScreen) (before Mill) (after Mill) (message (List String)))
      (→ MillScreen)
      (let* ((screen (MillScreen-mill-set screen after))
             (screen (MillScreen-forecast-set screen (forecast after)))
             (screen (MillScreen-message-set screen message))
             (screen (MillScreen-fresh-set screen (newly-heard before after))))
        (MillScreen-version-set screen (+ (● screen version) 1))))

    (define (press (screen MillScreen) (action I32)) (→ MillScreen)
      (cond ((guide-action? action)
             (MillScreen-guide-set screen
                                   (turn-guide (● screen guide) guide-pages action)))
            ((>= action action-choose)
             (MillScreen-selected-set screen (Some (i32->i64 (- action action-choose)))))
            ((= action action-restart)
             (new-mill-screen (● (● screen mill) scenario)
                              (+ (● screen version) 1)
                              (● screen width)
                              (● screen height)))
            ((= action action-wait) (act screen (Wait)))
            (else (match (● screen selected)
                    ((Some person) (act screen (person-action action person)))
                    ((None) (MillScreen-message-set screen (list "Click a person first.")))))))

    (define (update-mill-screen (screen MillScreen) (input Input)) (→ MillScreen)
      (match input
        ((Resize width height) (MillScreen-height-set (MillScreen-width-set screen width) height))
        ((PointerMove pointer x y) (MillScreen-hover-set screen (pick screen x y)))
        ((PointerDown pointer x y button)
         (match (pick screen x y)
           ((Some person) (MillScreen-selected-set screen (Some person)))
           ((None) screen)))
        ((Press action argument) (press screen action))
        (_ screen)))

    ;; ---- Town ----

    ;; The map is drawn in its own colors, unlit. Seen straight down, what
    ;; lies higher hides what lies below: ties, then markers and rings, then
    ;; bases, then figures, nearer the bottom of the map over farther, and
    ;; pips over all.
    (define (flat (thing Item)) (→ Item)
      (Item-glow-set thing 1.0))

    (define dark (rgb 70 78 92))

    ;; A thin box from a to b on the ground. A box's length runs along x, and
    ;; the renderer turns x toward (cos yaw, -sin yaw).
    (define (segment (a Vec3) (b Vec3)) (→ Item)
      (let* ((dx (- (● b x) (● a x))) (dz (- (● b z) (● a z))))
        (flat
         (item (Box) (Vec3 (* 0.5 (+ (● a x) (● b x))) 0.0 (* 0.5 (+ (● a z) (● b z))))
               (Vec3 (sqrt (+ (* dx dx) (* dz dz))) 0.01 0.08)
               (f64->f32 (atan2 (f32->f64 (negate dz)) (f32->f64 dx)))
               dark))))

    (define (tie-items) (→ (List Item))
      (map (lambda (tie) (segment (person-point (● tie first)) (person-point (● tie second))))
           ties))

    (define (audience-color (audience I64)) (→ I32)
      (list-ref (list (rgb 220 160 60) (rgb 60 170 180) (rgb 160 120 220)) audience))

    ;; A hub's base is larger.
    (define (base-size (person I64)) (→ F32)
      (if (hub? person) 1.7 1.3))

    ;; A flat hexagon around a person's feet, `size` across, its top at
    ;; `height`.
    (define (hexagon (person I64) (size F32) (height F32) (color I32)) (→ Item)
      (flat (item (Prism) (person-point person) (Vec3 size height size) 0.0 color)))

    ;; Pips over a person's head for what they believe on one pair of
    ;; traits, one pip per point of intensity, colored by trait: the danger
    ;; pair grows leftward from the middle, the word pair rightward.
    (define (pips (mill Mill)
                  (person I64)
                  (first Trait)
                  (second Trait)
                  (first-color I32)
                  (second-color I32)
                  (direction F32))
      (→ (List Item))
      (let* ((a (belief mill person first))
             (b (belief mill person second))
             (at (person-point person))
             (color (if (> a 0) first-color second-color)))
        (map (lambda (index)
               (flat (item (Tile)
                           (Vec3 (+ (● at x) (* direction (+ 0.24 (* 0.36 (i64->f32 index)))))
                                 0.6
                                 (- (● at z) 1.55))
                           (Vec3 0.3 1.0 0.3) 0.0 color)))
             (iota (max a b)))))

    ;; A person is their figure on their audience's base. Those who heard
    ;; something new stroll in place on a yellow ring; quiet ones stand on a
    ;; dark one, which wins for a quiet person who heard something, as
    ;; keeping quiet lasts while the news is one shift's, and the stroll
    ;; still shows it.
    (define (person-items (screen MillScreen) (person I64)) (→ (List Item))
      (let* ((mill (● screen mill)) (at (person-point person)) (size (base-size person))
             (fresh? (member? person (● screen fresh)))
             (layer (+ 0.1 (* 0.01 (- (● at z) town-top)))))
        (concatenate
         (list (list (hexagon person size 0.03 (audience-color (audience-of person)))
                     (pose-flat (walk-book (person-picture person)) (if fresh? (Stroll) (Stand))
                                (Vec3 (● at x) layer (+ (● at z) feet-offset))
                                toward-viewer
                                figure-size
                                (camera-of screen)))
               (pips mill person (Dangerous) (Harmless) (rgb 225 70 60) (rgb 140 190 245) -1.0)
               (pips mill person (Reliable) (Unreliable) (rgb 90 205 110) (rgb 245 150 40) 1.0)
               (cond
                ((quiet? mill person) (list (hexagon person (+ size 0.45) 0.02 (rgb 30 30 36))))
                (fresh? (list (hexagon person (+ size 0.45) 0.02 (rgb 235 205 70))))
                (else (Nil)))))))

    ;; The chosen person's base has a pale border, the one under the pointer
    ;; a grey one.
    (define (marker-items (screen MillScreen)) (→ (List Item))
      (append (match (● screen selected)
                ((Some person)
                 (list (hexagon person (+ (base-size person) 0.8) 0.015 (rgb 190 200 215))))
                ((None) (Nil)))
              (match (● screen hover)
                ((Some person)
                 (list (hexagon person (+ (base-size person) 0.65) 0.016 (rgb 110 118 132))))
                ((None) (Nil)))))

    (define (marker-version (screen MillScreen)) (→ I32)
      (let ((code (lambda (choice) (match choice ((Some person) (+ person 1)) ((None) 0)))))
        (i64->i32 (+ (* 32 (code (● screen selected))) (code (● screen hover))))))

    ;; `art` gives the bytes of each sheet the cast wears.
    (define (view-mill-screen (screen MillScreen) (art (Fn String → (Option Source))))
      (→ Frame)
      (Frame (camera-of screen) sunlight backdrop 1.0
             (list (Batch 0 0 (Solid) tie-items)
                   (Batch 1 (i64->i32 (● screen version)) (Solid)
                          (lambda ()
                            (concatenate (map (lambda (person) (person-items screen person))
                                              (iota person-count)))))
                   (Batch 2 (marker-version screen) (Solid) (lambda () (marker-items screen))))
             (map (lambda (person) (walk-picture art (person-picture person) (resident person)))
                  (iota person-count))))

    ;; ---- Status ----

    ;; The scenario, with the shift and coins as dials.
    (define (status-panel (screen MillScreen)) (→ Panel)
      (let* ((mill (● screen mill)) (shift (● mill shift)) (last (last-shift mill)))
        (Panel "status" (At (TopLeft) 0)
               (list (label "title" (● (scenario-rules (● mill scenario)) name))
                     (Dial (look "shift")
                           (string-append "Shift " (show (min shift last)) " of " (show last))
                           (/ (i64->f32 (- shift 1)) (i64->f32 last)))
                     (Dial (look "coins")
                           (string-append (show (● mill coins)) " coins")
                           (/ (i64->f32 (● mill coins)) 10.0))))))

    ;; The goal as a checklist, and when it is judged.
    (define (goal-panel (mill Mill)) (→ Panel)
      (Panel "goal" (At (TopLeft) 0)
             (Cons (section-heading "goal" "Goal")
                   (append (map-indexed goal-label (mill-goals mill))
                           (list (toned "deadline"
                                        (Muted)
                                        (● (scenario-rules (● mill scenario)) deadline)))))))

    (define (goal-label (index I64) (goal Goal)) (→ Widget)
      (let ((key (string-append "goal-" (show index))) (text (● goal text)))
        (match (● goal progress)
          ((Met) (toned key (Good) (string-append "✓ " text)))
          ((Done) (toned key (Good) (string-append "✓ " text)))
          ((Unmet) (toned key (Danger) (string-append "✗ " text)))
          ((Due) (toned key (Warning) (string-append "! " text ": now")))
          ((Upcoming) (toned key (Muted) (string-append "○ " text))))))

    ;; What to do now: the result once the game is over, the duty of a
    ;; forced shift, or the next step of a move.
    (define (hint (screen MillScreen)) (→ Widget)
      (let ((mill (● screen mill)) (chosen (● screen selected)))
        (match (mill-result mill)
          ((Some (Pair won? text))
           (toned "hint"
                  (if won? (Good) (Danger))
                  (string-append text " Restart, or go back to the menu.")))
          ((None)
           (if (forced? mill)
               (toned "hint" (Warning) (duty-text chosen))
               (toned "hint" (Plain) (step-text chosen)))))))

    ;; The forced shift's duty, toward the chosen person if they are in the
    ;; Docks.
    (define (duty-text (chosen (Option I64))) (→ String)
      (match chosen
        ((Some person) (if (= (audience-of person) docks)
                           (string-append "Rough up or threaten "
                                          (first-name person)
                                          ": this shift you must.")
                           (duty-text (None))))
        ((None)
         "This shift you must rough someone up or make a threat in the Docks: choose someone on a teal base.")))

    (define (step-text (chosen (Option I64))) (→ String)
      (match chosen
        ((Some person)
         (string-append "Choose what to do toward "
                        (first-name person)
                        ", who will tell their ties at the end of next shift. Or lie low."))
        ((None) "Choose a person on the map: they will witness what you do. Or lie low.")))

    ;; What the last shift did, under the moves that made it.
    (define (last-panel (screen MillScreen)) (→ Panel)
      (Panel "last" (At (TopLeft) 0)
             (match (● screen message)
               ((Nil) (list (toned "last-none" (Muted) "Nothing has happened yet.")))
               (texts (Cons (section-heading "last" "Last shift") (line-labels "last" texts))))))

    ;; ---- Moves ----

    ;; The move button `number` makes toward the chosen person, if anyone
    ;; is chosen.
    (define (toward-chosen (screen MillScreen) (number I32)) (→ (Option Action))
      (match (● screen selected)
        ((Some person) (Some (person-action number person)))
        ((None) (None))))

    ;; A move's button is greyed out with the reason when it cannot be made
    ;; now, and otherwise says what it will do. `move` is None for a move
    ;; that needs a person while no one is chosen.
    (define (move-button (screen MillScreen)
                         (key String)
                         (text String)
                         (caption String)
                         (number I32)
                         (move (Option Action)))
      (→ Widget)
      (match move
        ((Some action)
         (choice-button key
                        text
                        caption
                        number
                        0
                        (refusal (● screen mill) action)
                        (move-help action)))
        ((None)
         (choice-button key text caption number 0 (Some "Choose a person on the map first.") ""))))

    (define (move-help (action Action)) (→ String)
      (match action
        ((Do deed person)
         (string-append (first-name person)
                        " witnesses it, and tells their ties at the end of next shift."))
        ((Pay person)
         (string-append (first-name person)
                        " forgets every story and keeps quiet for four shifts. It is a liability."))
        ((Mislead trait person)
         (string-append (first-name person)
                        " hears a story you did not earn. It is exposed if they hear the truth."))
        ((Wait) "Do nothing this shift; stories still spread.")))

    (define (move-buttons (screen MillScreen)) (→ (List Widget))
      (append (map-indexed (lambda (index deed)
                             (let ((number (+ action-deed (i64->i32 index))))
                               (move-button screen
                                            (string-append "deed-" (show index))
                                            (deed-name deed)
                                            (deed-effect deed)
                                            number
                                            (toward-chosen screen number))))
                           deeds)
              (list (move-button screen
                                 "pay"
                                 "Pay to forget"
                                 "2 coins"
                                 action-pay
                                 (toward-chosen screen action-pay))
                    (move-button screen
                                 "lie-reliable"
                                 "Lie: you are reliable"
                                 "reliable 1"
                                 action-lie-reliable
                                 (toward-chosen screen action-lie-reliable))
                    (move-button screen
                                 "lie-harmless"
                                 "Lie: you are harmless"
                                 "harmless 1"
                                 action-lie-harmless
                                 (toward-chosen screen action-lie-harmless))
                    (move-button screen "wait" "Lie low" "do nothing" action-wait (Some (Wait))))))

    (define (action-panel (screen MillScreen)) (→ Panel)
      (Panel "actions" (At (TopLeft) 0)
             (append (Cons (section-heading "moves" "Your move: one per shift")
                           (if (mill-over? (● screen mill)) (Nil) (move-buttons screen)))
                     (list (button "restart" "Restart" action-restart)))))

    ;; ---- People ----

    ;; The person under the pointer, or else the chosen one: portrait, name,
    ;; audience, beliefs as chips, the stories they hold, and their ties.
    (define (person-panel (screen MillScreen)) (→ Panel)
      (Panel "person" (At (TopRight) 0)
             (match (match (● screen hover)
                      ((Some person) (Some person))
                      ((None) (● screen selected)))
               ((Some person) (person-widgets (● screen mill) person))
               ((None)
                (list (toned "person-none"
                             (Muted)
                             "Point at a person to see who they are, what they believe and where they heard it."))))))

    (define (person-widgets (mill Mill) (person I64)) (→ (List Widget))
      (concatenate
       (list (list (portrait "portrait" (person-picture person) 2)
                   (label (string-append "audience-" (show (audience-of person)))
                          (string-append (person-name person)
                                         "\n"
                                         (audience-name (audience-of person))
                                         (if (hub? person)
                                             "\nA hub: passes stories two steps"
                                             ""))))
             (section "believes" "Believes" "Nothing about you."
                      (map (lambda (belief)
                             (label (string-append "chip-" (trait-name (● belief first)))
                                    (belief-text belief)))
                           (person-beliefs mill person)))
             (match (story-lines mill person)
               ((Nil) (Nil))
               (stories (Cons (section-heading "stories" "Stories they hold")
                              (line-labels "story" stories))))
             (Cons (section-heading "ties" "Ties")
                   (map (lambda (tie)
                          (button (string-append "choose-" (show tie))
                                  (first-name tie)
                                  (+ action-choose (i64->i32 tie))))
                        (neighbors person))))))

    ;; ---- Beliefs and outlook ----

    ;; "reliable 2".
    (define (belief-text (belief (Pair Trait I64))) (→ String)
      (string-append (trait-name (● belief first)) " " (show (● belief second))))

    ;; What each audience believes, beside its color.
    (define (audience-panel (screen MillScreen)) (→ Panel)
      (Panel "audiences" (At (TopRight) 0)
             (Cons (section-heading "audiences" "What each audience believes")
                   (map (lambda (audience)
                          (label (string-append "audience-" (show audience))
                                 (string-append (audience-name audience) ": "
                                                (match (audience-beliefs (● screen mill)
                                                                         audience)
                                                  ((Nil) "nothing yet")
                                                  (beliefs
                                                   (string-join (map belief-text beliefs) ", "))))))
                        audiences))))

    ;; What would change if you lay low, and what could come back to bite.
    (define (outlook-panel (screen MillScreen)) (→ Panel)
      (let ((mill (● screen mill)))
        (Panel "outlook" (At (TopRight) 0)
               (append (if (mill-over? mill)
                           (Nil)
                           (section "forecast"
                                    "If you lie low"
                                    "Nothing changes."
                                    (line-labels "forecast" (● screen forecast))))
                       (section "liabilities"
                                "Liabilities"
                                "None yet."
                                (line-labels "liability" (liabilities mill)))))))

    ;; The colors of the pips and rings on the map.
    (define key-panel
      (Panel "key" (At (TopRight) 0)
             (list (label "chip-dangerous" "dangerous")
                   (label "chip-harmless" "harmless")
                   (label "chip-reliable" "reliable")
                   (label "chip-unreliable" "unreliable")
                   (label "ring-heard" "just heard")
                   (label "ring-quiet" "quiet"))))

    ;; ---- Guide ----

    (define guide-pages (→ (List Page))
      (list (Page "What this experiment tests"
                  (list
                   "The rumor mill asks one question: is steering what people believe fun, and can you predict it? If it is not, nothing else in Hearsay will save it."
                   "While you play, notice: do you plan several shifts ahead, or one at a time? Does the forecast help you think, or play the game for you? Do your payments and lies come back to bite?")
                  (Nil))
            (Page "The town"
                  (list
                   "Each figure is a person. Their base is their audience: amber for the Market, teal for the Docks, violet for the Tower."
                   "Lines are ties: people pass stories only to those they are tied to. Big bases are hubs, who pass a story two steps at once.")
                  (list (portrait "guide-portrait" (person-picture 13) 2)
                        (label "guide-caption" "Nia, the dock foreman, is a hub.")))
            (Page "Stories"
                  (list
                   "Everything you do becomes a story about you: a trait and a strength from 1 to 3."
                   "The witness keeps it to themselves for a shift, then tells their ties at the end of the next one. A story grows by 1 each time it crosses into another audience."
                   "Point at anyone to see the stories they hold and the path each took to reach them.")
                  (Nil))
            (Page "Beliefs"
                  (list
                   "Each person believes the strongest story they hold on each pair: dangerous against harmless, reliable against unreliable. On a tie, first impressions stick."
                   "Pips over a head show those beliefs, one per point: red dangerous, blue harmless, green reliable, orange unreliable."
                   "An audience believes a trait at level N when four of its eight people believe it at N or more. The top right shows each audience's levels, and further down, what will change if you lie low.")
                  (Nil))
            (Page "Your move"
                  (list
                   "Each shift you make one move. Choose a person on the map, then do something they witness, pay them 2 coins to forget and keep quiet for four shifts, or lie to them. Or lie low."
                   "Payments and lies are liabilities. A lie is exposed while its listener holds a true story of the opposite trait, and each exposed lie makes their audience believe you more unreliable."
                   "The goal at the top left shows how you stand, and the line under it says what to do next. A greyed-out move says why when you point at it.")
                  (Nil))))

    ;; `first` are panels to show before the screen's own.
    (define (mill-screen-hud (screen MillScreen) (first (List Panel))) (→ (List Panel))
      (concatenate
       (list first
             (list (status-panel screen)
                   (goal-panel (● screen mill))
                   (Panel "hint" (At (TopLeft) 0) (list (hint screen)))
                   (action-panel screen)
                   (last-panel screen)
                   (audience-panel screen)
                   key-panel
                   (person-panel screen)
                   (outlook-panel screen))
             (guide-panels "Rumor mill" guide-pages (● screen guide)))))

    ))
