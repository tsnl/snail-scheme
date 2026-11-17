;; The rumor mill in the browser: the town as a 2D map of its people, each a
;; figure on a base in their audience's color, with pips over their head
;; for what they believe. Around it, the HUD says what to do next, how the
;; goal stands, who the chosen person is and what they have heard, and
;; what each audience believes, with a button for each move that says why
;; when it cannot be made. A guide explains the game the first time.
(define-library (apps hearsay mill-screen)
  (export
   MillScreen
   new-mill-screen
   update-mill-screen
   mill-pictures
   mill-view
   mill-quads
   mill-screen-hud)
  (import
   (snail core base)
   (snail shell wire)
   (snail shell app)
   (snail shell math)
   (snail shell sprite)
   (snail shell graphics pod)
   (only (snail shell graphics atlas) Atlas Picture Source)
   (only (snail shell graphics quad) Quad View2D)
   (only (lpc layout) Stand Stroll walk-book)
   (lpc wardrobe)
   (apps hearsay mill)
   (apps hearsay cast)
   (apps hearsay hud)
   (apps hearsay drawing))
  (begin

    ;; ---- State ----

    ;; `message` is what the last shift did, a line each, or why it could
    ;; not be taken. `fresh` lists who heard something new in it. The
    ;; forecast takes simulating several shifts, so it is worked out once
    ;; per shift rather than every frame. `guide` is the guide's open page,
    ;; if any.
    (record MillScreen
      ((mill Mill)
       (forecast (List String))
       (selected (Option I64))
       (hover (Option I64))
       (message (List String))
       (fresh (List I64))
       (guide (Option I64))
       (width I32)
       (height I32))
      (deriving Serialize Deserialize))

    (define (new-mill-screen (scenario Scenario) (width I32) (height I32))
      (→ MillScreen)
      (let ((mill (new-mill scenario)))
        (new MillScreen
          (mill mill)
          (forecast (forecast mill))
          (selected (None))
          (hover (None))
          (message (Nil))
          (fresh (Nil))
          (guide (None))
          (width width)
          (height height))))

    ;; ---- Layout ----

    ;; The town is a map seen straight down by an orthographic camera,
    ;; scaled to fill the middle of the screen between the HUD's columns.
    ;; Its extent on the ground, with room above the top ring for heads and
    ;; pips:
    (define town-left (→ F32) -10.2)
    (define town-right (→ F32) 10.2)
    (define town-top (→ F32) -11.4)
    (define town-bottom (→ F32) 6.0)

    ;; The pixels each HUD column takes from a side of the screen: a panel's
    ;; 300 and its margin, or a fifth of a narrow screen, where they overlap
    ;; the map rather than shrink it to nothing.
    (define (hud-column (width F32)) (→ F32)
      (if (< width 800.0) (* 0.2 width) 318.0))

    (define (pixels-per-unit (screen MillScreen)) (→ F32)
      (let* ((width (max 1.0 (i32->f32 (● screen width))))
             (height (max 1.0 (i32->f32 (● screen height))))
             (across (max 120.0 (- width (* 2.0 (hud-column width)))))
             (down (max 120.0 (- height 24.0))))
        (min (/ across (- town-right town-left)) (/ down (- town-bottom town-top)))))

    (define town-x (→ F32) (/ (+ town-left town-right) 2.0))
    (define town-z (→ F32) (/ (+ town-top town-bottom) 2.0))

    ;; The camera picking casts rays from, and the same view in the plane
    ;; of the screen, where a ground point (x, z) lies at (x, -z): the
    ;; camera looks straight down, with -z up the screen.

    (define (camera-of (screen MillScreen)) (→ Camera)
      (new Camera
        (eye (new Vec3 (x town-x) (y 40.0) (z town-z)))
        (target (new Vec3 (x town-x) (y 0.0) (z town-z)))
        (projection
         (Orthographic (/ (max 1.0 (i32->f32 (● screen height))) (pixels-per-unit screen))))))

    (define (mill-view (screen MillScreen)) (→ View2D)
      (let ((width (max 1.0 (i32->f32 (● screen width))))
            (height (max 1.0 (i32->f32 (● screen height))))
            (scale (pixels-per-unit screen)))
        (new View2D
          (center (new Vec2f (x town-x) (y (negate town-z))))
          (extent (new Vec2f (x (/ width scale)) (y (/ height scale))))
          (pixels (new Vec2f (x width) (y height))))))

    ;; Audiences sit on a triangle, each person on a ring of radius 2.8.
    (define (person-point (person I64)) (→ Vec3)
      (let* ((audience (audience-of person))
             (cx (list-ref (list -6.3 6.3 0.0) audience))
             (cz (list-ref (list 2.4 2.4 -6.2) audience))
             (angle (* (i64->f64 (remainder person 8)) (/ pi 4.0))))
        (new Vec3
          (x (f64->f32 (+ cx (* 2.8 (cos angle)))))
          (y 0.0)
          (z (f64->f32 (+ cz (* 2.8 (sin angle))))))))

    ;; A figure's cell is `figure-size` units square. Its feet stand at the
    ;; middle of its base, a little above the cell's bottom edge, and its
    ;; body fills about the middle half of the cell's width.
    (define figure-size (→ F32) 2.0)
    (define feet-offset (→ F32) 0.35)

    ;; Everyone faces the viewer, down the map.
    (define toward-viewer (→ Vec3) (new Vec3 (x 0.0) (y 0.0) (z 1.0)))

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
        (and (< across (* 0.32 figure-size))
             (< down 0.7)
             (> down (negate (* 0.85 figure-size))))))

    ;; ---- Actions ----

    ;; Buttons 1 to 5 are the deeds in order, 6 pays, 7 and 8 lie, 9 lies
    ;; low, 10 restarts, and 100 + p chooses person p.
    (define action-deed (→ I32) 1)
    (define action-pay (→ I32) 6)
    (define action-lie-reliable (→ I32) 7)
    (define action-lie-harmless (→ I32) 8)
    (define action-wait (→ I32) 9)
    (define action-restart (→ I32) 10)
    (define action-choose (→ I32) 100)

    (define (person-action (action I32) (person I64)) (→ Action)
      (cond
       ((< action action-pay) (Do (list-ref deeds (i32->i64 (- action action-deed))) person))
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
             (screen (MillScreen-message-set screen message)))
        (MillScreen-fresh-set screen (newly-heard before after))))

    (define (press (screen MillScreen) (action I32)) (→ MillScreen)
      (cond ((guide-action? action)
             (MillScreen-guide-set screen
                                   (turn-guide (● screen guide) guide-pages action)))
            ((>= action action-choose)
             (MillScreen-selected-set screen (Some (i32->i64 (- action action-choose)))))
            ((= action action-restart)
             (new-mill-screen (● (● screen mill) scenario) (● screen width) (● screen height)))
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

    ;; The map is drawn in its own colors, as quads, each covering those
    ;; before it: ties, then markers and rings, then bases, then figures,
    ;; nearer the bottom of the map over farther, and pips over all.

    (define dark (→ I32) (rgb 70 78 92))

    ;; A thin bar from a to b on the ground.
    (define (segment (atlas Atlas) (a Vec3) (b Vec3)) (→ (Option Quad))
      (let* ((dx (- (● b x) (● a x))) (dz (- (● b z) (● a z))))
        (tinted atlas
                white
                (None)
                (* 0.5 (+ (● a x) (● b x)))
                (negate (* 0.5 (+ (● a z) (● b z))))
                (sqrt (+ (* dx dx) (* dz dz)))
                0.08
                (f64->f32 (atan2 (f32->f64 (negate dz)) (f32->f64 dx)))
                dark)))

    (define (tie-quads (atlas Atlas)) (→ (List (Option Quad)))
      (map (lambda (tie) (segment atlas (person-point (● tie first)) (person-point (● tie second))))
           ties))

    (define (audience-color (audience I64)) (→ I32)
      (list-ref (list (rgb 220 160 60) (rgb 60 170 180) (rgb 160 120 220)) audience))

    ;; A hub's base is larger.
    (define (base-size (person I64)) (→ F32)
      (if (hub? person) 1.7 1.3))

    ;; A hexagon around a person's feet, `size` from point to point.
    (define (hexagon-quad (atlas Atlas) (person I64) (size F32) (color I32)) (→ (Option Quad))
      (let ((at (person-point person)))
        (tinted atlas hexagon (None) (● at x) (negate (● at z)) size size 0.0 color)))

    ;; Pips over a person's head for what they believe on one pair of
    ;; traits, one pip per point of intensity, colored by trait: the danger
    ;; pair grows leftward from the middle, the word pair rightward.
    (define (pips (atlas Atlas)
                  (mill Mill)
                  (person I64)
                  (first Trait)
                  (second Trait)
                  (first-color I32)
                  (second-color I32)
                  (direction F32))
      (→ (List (Option Quad)))
      (let* ((a (belief mill person first))
             (b (belief mill person second))
             (at (person-point person))
             (color (if (> a 0) first-color second-color)))
        (map (lambda (index)
               (tinted atlas
                       white
                       (None)
                       (+ (● at x) (* direction (+ 0.24 (* 0.36 (i64->f32 index)))))
                       (negate (- (● at z) 1.55))
                       0.3
                       0.3
                       0.0
                       color))
             (iota (max a b)))))

    (define (pip-quads (atlas Atlas) (mill Mill) (person I64)) (→ (List (Option Quad)))
      (append (pips atlas mill person (Dangerous) (Harmless) (rgb 225 70 60) (rgb 140 190 245) -1.0)
              (pips atlas
                    mill
                    person
                    (Reliable)
                    (Unreliable)
                    (rgb 90 205 110)
                    (rgb 245 150 40)
                    1.0)))

    ;; Those who heard something new stroll in place on a yellow ring; quiet
    ;; ones stand on a dark one, which wins for a quiet person who heard
    ;; something, as keeping quiet lasts while the news is one shift's, and
    ;; the stroll still shows it.
    (define (ring-quads (atlas Atlas) (screen MillScreen) (person I64)) (→ (List (Option Quad)))
      (let ((size (+ (base-size person) 0.45)))
        (cond
         ((quiet? (● screen mill) person) (list (hexagon-quad atlas person size (rgb 30 30 36))))
         ((member? person (● screen fresh))
          (list (hexagon-quad atlas person size (rgb 235 205 70))))
         (else (Nil)))))

    ;; A person's figure, its feet at the middle of their base, facing the
    ;; viewer.
    (define (figure-quad (atlas Atlas) (screen MillScreen) (person I64) (time I64))
      (→ (Option Quad))
      (let ((at (person-point person))
            (gait (if (member? person (● screen fresh)) (Stroll) (Stand))))
        (tinted atlas
                (person-picture person)
                (Some (cell-at (walk-book (person-picture person)) gait (heading 4 0.0 -1.0) time))
                (● at x)
                (+ (negate (+ (● at z) feet-offset)) (/ figure-size 2.0))
                figure-size
                figure-size
                0.0
                (rgb 255 255 255))))

    ;; The chosen person's base has a pale border, the one under the pointer
    ;; a grey one over it.
    (define (marker-quads (atlas Atlas) (screen MillScreen)) (→ (List (Option Quad)))
      (append (match (● screen selected)
                ((Some person)
                 (list (hexagon-quad atlas person (+ (base-size person) 0.8) (rgb 190 200 215))))
                ((None) (Nil)))
              (match (● screen hover)
                ((Some person)
                 (list (hexagon-quad atlas person (+ (base-size person) 0.65) (rgb 110 118 132))))
                ((None) (Nil)))))

    ;; The town at `time` milliseconds, in drawing order.
    (define (mill-quads (screen MillScreen) (atlas Atlas) (time I64)) (→ (List Quad))
      (let ((people (iota person-count))
            (far-first (list-sort (lambda (a b) (< (● (person-point a) z) (● (person-point b) z)))
                                  (iota person-count))))
        (present
         (concatenate
          (list (tie-quads atlas)
                (marker-quads atlas screen)
                (concatenate (map (lambda (person) (ring-quads atlas screen person)) people))
                (map (lambda (person)
                       (hexagon-quad atlas
                                     person
                                     (base-size person)
                                     (audience-color (audience-of person))))
                     people)
                (map (lambda (person) (figure-quad atlas screen person time)) far-first)
                (concatenate
                 (map (lambda (person) (pip-quads atlas (● screen mill) person)) people)))))))

    ;; The quads whose pictures the atlas holds.
    (define (present (quads (List (Option Quad)))) (→ (List Quad))
      (concatenate (map (lambda (quad)
                          (match quad
                            ((Some it) (list it))
                            ((None) (Nil))))
                        quads)))

    ;; `art` gives the bytes of each sheet the cast wears.
    (define (mill-pictures (art (Fn String → (Option Source)))) (→ (List Picture))
      (map (lambda (person) (walk-picture art (person-picture person) (resident person)))
           (iota person-count)))

    ;; ---- Status ----

    ;; The scenario, with the shift and coins as dials.
    (define (status-panel (screen MillScreen)) (→ Panel)
      (let* ((mill (● screen mill)) (shift (● mill shift)) (last (last-shift mill)))
        (new Panel (key "status") (place (At (TopLeft) 0))
             (widgets (list (label "title" (● (scenario-rules (● mill scenario)) name))
                            (Dial (look "shift")
                                  (string-append "Shift "
                                                 (show (min shift last))
                                                 " of "
                                                 (show last))
                                  (/ (i64->f32 (- shift 1)) (i64->f32 last)))
                            (Dial (look "coins")
                                  (string-append (show (● mill coins)) " coins")
                                  (/ (i64->f32 (● mill coins)) 10.0)))))))

    ;; The goal as a checklist, and when it is judged.
    (define (goal-panel (mill Mill)) (→ Panel)
      (new Panel (key "goal") (place (At (TopLeft) 0))
           (widgets (Cons (section-heading "goal" "Goal")
                          (append (map-indexed goal-label (mill-goals mill))
                                  (list (toned "deadline"
                                               (Muted)
                                               (● (scenario-rules (● mill scenario))
                                                  deadline))))))))

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
      (new Panel (key "last") (place (At (TopLeft) 0))
           (widgets (match (● screen message)
                      ((Nil) (list (toned "last-none" (Muted) "Nothing has happened yet.")))
                      (texts
                       (Cons (section-heading "last" "Last shift") (line-labels "last" texts)))))))

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
                    (move-button screen
                                 "wait"
                                 "Lie low"
                                 "do nothing"
                                 action-wait
                                 (Some (Wait))))))

    (define (action-panel (screen MillScreen)) (→ Panel)
      (new Panel (key "actions") (place (At (TopLeft) 0))
           (widgets (append (Cons (section-heading "moves" "Your move: one per shift")
                                  (if (mill-over? (● screen mill)) (Nil) (move-buttons screen)))
                            (list (button "restart" "Restart" action-restart))))))

    ;; ---- People ----

    ;; The person under the pointer, or else the chosen one: portrait, name,
    ;; audience, beliefs as chips, the stories they hold, and their ties.
    (define (person-panel (screen MillScreen)) (→ Panel)
      (new Panel (key "person") (place (At (TopRight) 0))
           (widgets (match (match (● screen hover)
                             ((Some person) (Some person))
                             ((None) (● screen selected)))
                      ((Some person) (person-widgets (● screen mill) person))
                      ((None)
                       (list (toned "person-none"
                                    (Muted)
                                    "Point at a person to see who they are, what they believe and where they heard it.")))))))

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
      (new Panel (key "audiences") (place (At (TopRight) 0))
           (widgets (Cons (section-heading "audiences" "What each audience believes")
                          (map (lambda (audience)
                                 (label (string-append "audience-" (show audience))
                                        (string-append (audience-name audience) ": "
                                                       (match (audience-beliefs (● screen mill)
                                                                                audience)
                                                         ((Nil) "nothing yet")
                                                         (beliefs
                                                          (string-join (map belief-text beliefs)
                                                                       ", "))))))
                               audiences)))))

    ;; What would change if you lay low, and what could come back to bite.
    (define (outlook-panel (screen MillScreen)) (→ Panel)
      (let ((mill (● screen mill)))
        (new Panel (key "outlook") (place (At (TopRight) 0))
             (widgets (append (if (mill-over? mill)
                                  (Nil)
                                  (section "forecast"
                                           "If you lie low"
                                           "Nothing changes."
                                           (line-labels "forecast" (● screen forecast))))
                              (section "liabilities"
                                       "Liabilities"
                                       "None yet."
                                       (line-labels "liability" (liabilities mill))))))))

    ;; The colors of the pips and rings on the map.
    (define key-panel (→ Panel)
      (new Panel (key "key") (place (At (TopRight) 0))
           (widgets (list (label "chip-dangerous" "dangerous")
                          (label "chip-harmless" "harmless")
                          (label "chip-reliable" "reliable")
                          (label "chip-unreliable" "unreliable")
                          (label "ring-heard" "just heard")
                          (label "ring-quiet" "quiet")))))

    ;; ---- Guide ----

    (define guide-pages (→ (List Page))
      (list (new Page (title "What this experiment tests")
                 (paragraphs (list
                              "The rumor mill asks one question: is steering what people believe fun, and can you predict it? If it is not, nothing else in Hearsay will save it."
                              "While you play, notice: do you plan several shifts ahead, or one at a time? Does the forecast help you think, or play the game for you? Do your payments and lies come back to bite?"))
                 (extras (Nil)))
            (new Page (title "The town")
                 (paragraphs (list
                              "Each figure is a person. Their base is their audience: amber for the Market, teal for the Docks, violet for the Tower."
                              "Lines are ties: people pass stories only to those they are tied to. Big bases are hubs, who pass a story two steps at once."))
                 (extras (list (portrait "guide-portrait" (person-picture 13) 2)
                               (label "guide-caption" "Nia, the dock foreman, is a hub."))))
            (new Page (title "Stories")
                 (paragraphs (list
                              "Everything you do becomes a story about you: a trait and a strength from 1 to 3."
                              "The witness keeps it to themselves for a shift, then tells their ties at the end of the next one. A story grows by 1 each time it crosses into another audience."
                              "Point at anyone to see the stories they hold and the path each took to reach them."))
                 (extras (Nil)))
            (new Page (title "Beliefs")
                 (paragraphs (list
                              "Each person believes the strongest story they hold on each pair: dangerous against harmless, reliable against unreliable. On a tie, first impressions stick."
                              "Pips over a head show those beliefs, one per point: red dangerous, blue harmless, green reliable, orange unreliable."
                              "An audience believes a trait at level N when four of its eight people believe it at N or more. The top right shows each audience's levels, and further down, what will change if you lie low."))
                 (extras (Nil)))
            (new Page (title "Your move")
                 (paragraphs (list
                              "Each shift you make one move. Choose a person on the map, then do something they witness, pay them 2 coins to forget and keep quiet for four shifts, or lie to them. Or lie low."
                              "Payments and lies are liabilities. A lie is exposed while its listener holds a true story of the opposite trait, and each exposed lie makes their audience believe you more unreliable."
                              "The goal at the top left shows how you stand, and the line under it says what to do next. A greyed-out move says why when you point at it."))
                 (extras (Nil)))))

    ;; `first` are panels to show before the screen's own.
    (define (mill-screen-hud (screen MillScreen) (first (List Panel))) (→ (List Panel))
      (concatenate
       (list first
             (list (status-panel screen)
                   (goal-panel (● screen mill))
                   (new Panel (key "hint") (place (At (TopLeft) 0)) (widgets (list (hint screen))))
                   (action-panel screen)
                   (last-panel screen)
                   (audience-panel screen)
                   key-panel
                   (person-panel screen)
                   (outlook-panel screen))
             (guide-panels "Rumor mill" guide-pages (● screen guide)))))

    ))
