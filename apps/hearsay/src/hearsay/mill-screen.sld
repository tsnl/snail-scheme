;; The rumor mill in the browser: the town as a 2D map of its people, each a
;; figure on a base in their audience's color, with pips over their head
;; for what they believe; the chosen person's portrait and stories; and
;; buttons for the shift's action.
(define-library (hearsay mill-screen)
  (export
   MillScreen
   new-mill-screen
   update-mill-screen
   view-mill-screen
   mill-screen-hud)
  (import
   (lofi base)
   (lofi wire)
   (lofi app)
   (lofi math)
   (lofi sprite)
   (only (lpc layout) Stand Stroll)
   (lpc wardrobe)
   (hearsay mill)
   (hearsay cast))
  (begin

    ;; ---- State ----

    ;; `fresh` lists who heard something new in the last shift. `summary`
    ;; holds the audiences, forecast and liabilities, which take simulating
    ;; several shifts, so they are worked out once per shift rather than
    ;; every frame. `version` changes with every shift, so the host redraws
    ;; the town only then.
    (struct MillScreen
      ((scenario I64)
       (mill Mill)
       (summary (List String))
       (selected (Option I64))
       (hover (Option I64))
       (message String)
       (fresh (List I64))
       (version I64)
       (width I32)
       (height I32))
      (deriving Serialize Deserialize))

    ;; `version` must differ from any town the host has drawn before.
    (: new-mill-screen (-> I64 I64 I32 I32 MillScreen))
    (define (new-mill-screen scenario version width height)
      (let ((mill (new-mill scenario)))
        (MillScreen scenario mill (summary mill) (None) (None) "Click a person to choose them, then choose what to do."
                    (Nil) version width height)))

    (: summary (-> Mill (List String)))
    (define (summary mill)
      (list (lines (mill-audiences mill)) (lines (mill-outlook mill)) (lines (liability-lines mill))))

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
    (: hud-column (-> F32 F32))
    (define (hud-column width)
      (if (< width 800.0) (* 0.2 width) 318.0))

    (: camera-of (-> MillScreen Camera))
    (define (camera-of screen)
      (let* ((width (max 1.0 (i32->f32 (MillScreen-width screen)))) (height (max 1.0 (i32->f32 (MillScreen-height screen))))
             (across (max 120.0 (- width (* 2.0 (hud-column width))))) (down (max 120.0 (- height 24.0)))
             (pixels-per-unit (min (/ across (- town-right town-left)) (/ down (- town-bottom town-top))))
             (x (/ (+ town-left town-right) 2.0)) (z (/ (+ town-top town-bottom) 2.0)))
        (Camera (Vec3 x 40.0 z) (Vec3 x 0.0 z) (Orthographic (/ height pixels-per-unit)))))

    (define sunlight (Light (Vec3 0.0 1.0 0.0) 0.0 1.0))

    ;; Audiences sit on a triangle, each person on a ring of radius 2.8.
    (: person-point (-> I64 Vec3))
    (define (person-point person)
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

    ;; Each person's picture.
    (: picture-key (-> I64 I32))
    (define (picture-key person)
      (i64->i32 (+ 100 person)))

    ;; The person whose figure or base is under the pointer, the one nearest
    ;; the bottom of the map when figures overlap.
    (: pick (-> MillScreen I32 I32 (Option I64)))
    (define (pick screen x y)
      (match (ground-point (camera-of screen) x y (MillScreen-width screen) (MillScreen-height screen))
        ((Some point)
         (fold-left (lambda (best person)
                      (if (and (over? point person) (match best ((Some other) (> (Vec3-z (person-point person)) (Vec3-z (person-point other)))) ((None) #t)))
                          (Some person)
                          best))
                    (None)
                    (iota person-count)))
        ((None) (None))))

    (: over? (-> Vec3 I64 Bool))
    (define (over? point person)
      (let* ((at (person-point person)) (across (abs (- (Vec3-x point) (Vec3-x at)))) (down (- (Vec3-z point) (Vec3-z at))))
        (and (< across (* 0.32 figure-size)) (< down 0.7) (> down (negate (* 0.85 figure-size))))))

    ;; ---- Actions ----

    ;; Buttons 1-5 are the deeds, 6 pays, 7 and 8 lie, 9 lies low, 10
    ;; restarts, and 100 + p chooses person p.
    (define action-pay 6)
    (define action-lie-reliable 7)
    (define action-lie-harmless 8)
    (define action-wait 9)
    (define action-restart 10)
    (define action-choose 100)

    (: person-action (-> I32 I64 Action))
    (define (person-action action person)
      (cond ((<= action 5) (Do (list-ref deeds (i32->i64 (- action 1))) person))
            ((= action action-pay) (Pay person))
            ((= action action-lie-reliable) (Mislead (Reliable) person))
            (else (Mislead (Harmless) person))))

    ;; Takes the shift, or shows why it cannot be taken.
    (: act (-> MillScreen Action MillScreen))
    (define (act screen action)
      (let ((before (MillScreen-mill screen)))
        (match (take-shift before action)
          ((Ok result) (record-shift screen before (Pair-first result) (Pair-second result)))
          ((Err message) (MillScreen-message-set screen message)))))

    ;; Remembers the new state, what it said, and who heard something new.
    (: record-shift (-> MillScreen Mill Mill String MillScreen))
    (define (record-shift screen before after message)
      (let* ((screen (MillScreen-mill-set screen after))
             (screen (MillScreen-summary-set screen (summary after)))
             (screen (MillScreen-message-set screen message))
             (screen (MillScreen-fresh-set screen (newly-heard before after))))
        (MillScreen-version-set screen (+ (MillScreen-version screen) 1))))

    (: press (-> MillScreen I32 MillScreen))
    (define (press screen action)
      (cond ((>= action action-choose) (MillScreen-selected-set screen (Some (i32->i64 (- action action-choose)))))
            ((= action action-restart)
             (new-mill-screen (MillScreen-scenario screen) (+ (MillScreen-version screen) 1) (MillScreen-width screen)
                              (MillScreen-height screen)))
            ((= action action-wait) (act screen (Wait)))
            (else (match (MillScreen-selected screen)
                    ((Some person) (act screen (person-action action person)))
                    ((None) (MillScreen-message-set screen "Click a person first."))))))

    (: update-mill-screen (-> MillScreen Input MillScreen))
    (define (update-mill-screen screen input)
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
    (: flat (-> Item Item))
    (define (flat thing)
      (Item-glow-set thing 1.0))

    (define dark (rgb 70 78 92))

    ;; A thin box from a to b on the ground. A box's length runs along x, and
    ;; the renderer turns x toward (cos yaw, -sin yaw).
    (: segment (-> Vec3 Vec3 Item))
    (define (segment a b)
      (let* ((dx (- (Vec3-x b) (Vec3-x a))) (dz (- (Vec3-z b) (Vec3-z a))))
        (flat (item (Box) (Vec3 (* 0.5 (+ (Vec3-x a) (Vec3-x b))) 0.0 (* 0.5 (+ (Vec3-z a) (Vec3-z b))))
                    (Vec3 (sqrt (+ (* dx dx) (* dz dz))) 0.01 0.08) (f64->f32 (atan2 (f32->f64 (negate dz)) (f32->f64 dx))) dark))))

    (: tie-items (-> (List Item)))
    (define (tie-items)
      (map (lambda (tie) (segment (person-point (Pair-first tie)) (person-point (Pair-second tie)))) ties))

    (: audience-color (-> I64 I32))
    (define (audience-color audience)
      (list-ref (list (rgb 220 160 60) (rgb 60 170 180) (rgb 160 120 220)) audience))

    ;; A hub's base is larger.
    (: base-size (-> I64 F32))
    (define (base-size person)
      (if (hub? person) 1.7 1.3))

    ;; A flat hexagon around a person's feet, `size` across, its top at
    ;; `height`.
    (: hexagon (-> I64 F32 F32 I32 Item))
    (define (hexagon person size height color)
      (flat (item (Prism) (person-point person) (Vec3 size height size) 0.0 color)))

    ;; Pips over a person's head for what they believe on one pair of
    ;; traits, one pip per point of intensity, colored by trait: the danger
    ;; pair grows leftward from the middle, the word pair rightward.
    (: pips (-> Mill I64 Trait Trait I32 I32 F32 (List Item)))
    (define (pips mill person first second first-color second-color direction)
      (let* ((a (belief mill person first)) (b (belief mill person second)) (at (person-point person))
             (color (if (> a 0) first-color second-color)))
        (map (lambda (index)
               (flat (item (Tile) (Vec3 (+ (Vec3-x at) (* direction (+ 0.24 (* 0.36 (i64->f32 index))))) 0.6 (- (Vec3-z at) 1.55))
                           (Vec3 0.3 1.0 0.3) 0.0 color)))
             (iota (max a b)))))

    ;; A person is their figure on their audience's base. Those who heard
    ;; something new stroll in place on a yellow ring; quiet ones stand on a
    ;; dark one, which wins for a quiet person who heard something, as
    ;; keeping quiet lasts while the news is one shift's, and the stroll
    ;; still shows it.
    (: person-items (-> MillScreen I64 (List Item)))
    (define (person-items screen person)
      (let* ((mill (MillScreen-mill screen)) (at (person-point person)) (size (base-size person))
             (fresh? (member? person (MillScreen-fresh screen)))
             (layer (+ 0.1 (* 0.01 (- (Vec3-z at) town-top)))))
        (concatenate
         (list (list (hexagon person size 0.03 (audience-color (audience-of person)))
                     (pose-flat (character-book (picture-key person)) (if fresh? (Stroll) (Stand))
                                (Vec3 (Vec3-x at) layer (+ (Vec3-z at) feet-offset)) toward-viewer figure-size (camera-of screen)))
               (pips mill person (Dangerous) (Harmless) (rgb 225 70 60) (rgb 140 190 245) -1.0)
               (pips mill person (Reliable) (Unreliable) (rgb 90 205 110) (rgb 245 150 40) 1.0)
               (cond ((quiet? mill person) (list (hexagon person (+ size 0.45) 0.02 (rgb 30 30 36))))
                     (fresh? (list (hexagon person (+ size 0.45) 0.02 (rgb 235 205 70))))
                     (else (Nil)))))))

    ;; The chosen person's base has a pale border, the one under the pointer
    ;; a grey one.
    (: marker-items (-> MillScreen (List Item)))
    (define (marker-items screen)
      (append (match (MillScreen-selected screen)
                ((Some person) (list (hexagon person (+ (base-size person) 0.8) 0.015 (rgb 190 200 215))))
                ((None) (Nil)))
              (match (MillScreen-hover screen)
                ((Some person) (list (hexagon person (+ (base-size person) 0.65) 0.016 (rgb 110 118 132))))
                ((None) (Nil)))))

    (: marker-version (-> MillScreen I32))
    (define (marker-version screen)
      (let ((code (lambda (choice) (match choice ((Some person) (+ person 1)) ((None) 0)))))
        (i64->i32 (+ (* 32 (code (MillScreen-selected screen))) (code (MillScreen-hover screen))))))

    ;; `art` gives the bytes of each sheet the cast wears.
    (: view-mill-screen (-> MillScreen (-> String (Option Source)) Frame))
    (define (view-mill-screen screen art)
      (Frame (camera-of screen) sunlight (rgb 16 20 28) 1.0
             (list (Batch 0 0 (Solid) tie-items)
                   (Batch 1 (i64->i32 (MillScreen-version screen)) (Solid)
                          (lambda () (concatenate (map (lambda (person) (person-items screen person)) (iota person-count)))))
                   (Batch 2 (marker-version screen) (Solid) (lambda () (marker-items screen))))
             (map (lambda (person) (walk-picture art (picture-key person) (resident person))) (iota person-count))))

    ;; ---- Panels ----

    (: label (-> String String Widget))
    (define (label key text)
      (Label (look key) text))

    (: button (-> String String I32 Widget))
    (define (button key text action)
      (Button (look key) text "" action 0 (Enabled) -1.0))

    (: lines (-> (List String) String))
    (define (lines texts)
      (string-join texts "\n"))

    ;; The person under the pointer, or else the chosen one, with buttons to
    ;; choose their ties.
    (: person-widgets (-> MillScreen (List Widget)))
    (define (person-widgets screen)
      (match (match (MillScreen-hover screen) ((Some person) (Some person)) ((None) (MillScreen-selected screen)))
        ((Some person)
         (Cons (portrait "portrait" (picture-key person) 2)
               (Cons (label "person" (look-text (MillScreen-mill screen) person))
                     (map (lambda (tie) (button (string-append "choose-" (show tie)) (string-append "Choose " (first-name tie))
                                                (+ action-choose (i64->i32 tie))))
                          (neighbors person)))))
        ((None) (list (label "person" "Point at a person to see what they believe and where they heard it.")))))

    ;; The deeds and the other actions, named for the chosen person.
    (: action-buttons (-> MillScreen (List Widget)))
    (define (action-buttons screen)
      (let ((whom (match (MillScreen-selected screen) ((Some person) (string-append " (" (first-name person) ")")) ((None) ""))))
        (append (map-indexed (lambda (index deed)
                               (button (string-append "deed-" (show index)) (string-append (deed-summary deed) whom) (i64->i32 (+ index 1))))
                             deeds)
                (list (button "pay" (string-append "Pay 2 coins" whom) action-pay)
                      (button "lie-reliable" (string-append "Lie: reliable 1" whom) action-lie-reliable)
                      (button "lie-harmless" (string-append "Lie: harmless 1" whom) action-lie-harmless)
                      (button "wait" "Lie low" action-wait)
                      (button "restart" "Restart" action-restart)))))

    (define legend
      (string-append "Pips over a head, one per point: red dangerous, blue harmless, green reliable, orange unreliable."
                     " Yellow ring: just heard something. Dark ring: quiet. Big base: hub."))

    ;; `first` are panels to show before the screen's own.
    (: mill-screen-hud (-> MillScreen (List Panel) (List Panel)))
    (define (mill-screen-hud screen first)
      (let ((mill (MillScreen-mill screen)))
        (append first
                (list (Panel "status" (At (TopLeft) 0)
                             (list (label "status" (lines (mill-status mill))) (label "message" (MillScreen-message screen))))
                      (Panel "person" (At (TopRight) 0) (person-widgets screen))
                      (Panel "actions" (At (BottomLeft) 0)
                             (if (mill-over? mill) (list (button "restart" "Restart" action-restart)) (action-buttons screen)))
                      (Panel "summary" (At (BottomRight) 0)
                             (map-indexed (lambda (index text) (label (string-append "summary-" (show index)) text))
                                          (append (MillScreen-summary screen) (list legend))))))))

    ))
