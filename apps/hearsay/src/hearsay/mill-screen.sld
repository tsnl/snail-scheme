;; The rumor mill in the browser: the town drawn as a graph, with pillars
;; over each person for what they believe, the chosen person's stories, and
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
   (hearsay mill))
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

    (define camera (Camera (Vec3 1.0 27.0 10.0) (Vec3 1.0 0.0 0.5) (Perspective 0.8)))

    (define sunlight (Light (Vec3 0.4 1.0 0.3) 0.65 0.45))

    ;; Audiences sit on a triangle, each person on a ring of radius 3.
    (: person-point (-> I64 Vec3))
    (define (person-point person)
      (let* ((audience (audience-of person))
             (cx (list-ref (list -7.0 7.0 0.0) audience))
             (cz (list-ref (list 3.0 3.0 -7.0) audience))
             (angle (* (i64->f64 (remainder person 8)) (/ pi 4.0))))
        (Vec3 (f64->f32 (+ cx (* 3.0 (cos angle)))) 0.0 (f64->f32 (+ cz (* 3.0 (sin angle)))))))

    (: square (-> F32 F32))
    (define (square x)
      (* x x))

    ;; The person within reach of the ground point under the pointer.
    (: pick (-> MillScreen I32 I32 (Option I64)))
    (define (pick screen x y)
      (match (ground-point camera x y (MillScreen-width screen) (MillScreen-height screen))
        ((Some point)
         (find (lambda (person)
                 (let ((at (person-point person)))
                   (< (+ (square (- (Vec3-x at) (Vec3-x point))) (square (- (Vec3-z at) (Vec3-z point)))) 1.4)))
               (iota person-count)))
        ((None) (None))))

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

    (define dark (rgb 70 78 92))

    ;; A thin box from a to b on the ground. A box's length runs along x, and
    ;; the renderer turns x toward (cos yaw, -sin yaw).
    (: segment (-> Vec3 Vec3 Item))
    (define (segment a b)
      (let* ((dx (- (Vec3-x b) (Vec3-x a))) (dz (- (Vec3-z b) (Vec3-z a))))
        (item (Box) (Vec3 (* 0.5 (+ (Vec3-x a) (Vec3-x b))) 0.0 (* 0.5 (+ (Vec3-z a) (Vec3-z b))))
              (Vec3 (sqrt (+ (* dx dx) (* dz dz))) 0.04 0.08) (f64->f32 (atan2 (f32->f64 (negate dz)) (f32->f64 dx))) dark)))

    (: tie-items (-> (List Item)))
    (define (tie-items)
      (map (lambda (tie) (segment (person-point (Pair-first tie)) (person-point (Pair-second tie)))) ties))

    (: audience-color (-> I64 I32))
    (define (audience-color audience)
      (list-ref (list (rgb 220 160 60) (rgb 60 170 180) (rgb 160 120 220)) audience))

    (: person-size (-> I64 F32))
    (define (person-size person)
      (if (hub? person) 1.1 0.8))

    ;; A pillar over a person for what they believe on one pair of traits:
    ;; its color is the trait and its height the intensity. The danger pair
    ;; stands on the left, the word pair on the right.
    (: pillar (-> Mill I64 Trait Trait I32 I32 F32 (List Item)))
    (define (pillar mill person first second first-color second-color side)
      (let* ((a (belief mill person first)) (b (belief mill person second)) (at (person-point person))
             (strength (max a b)))
        (if (= strength 0)
            (Nil)
            (list (item (Box) (Vec3 (+ (Vec3-x at) side) (person-size person) (Vec3-z at))
                        (Vec3 0.42 (* 0.7 (i64->f32 strength)) 0.42) 0.0 (if (> a 0) first-color second-color))))))

    ;; Quiet people stand on a dark square, and those who heard something
    ;; new on a yellow one.
    (: person-items (-> MillScreen I64 (List Item)))
    (define (person-items screen person)
      (let* ((mill (MillScreen-mill screen)) (at (person-point person)) (size (person-size person)))
        (append (Cons (item (Sphere) at (Vec3 size size size) 0.0 (audience-color (audience-of person)))
                      (append (pillar mill person (Dangerous) (Harmless) (rgb 225 70 60) (rgb 140 190 245) -0.3)
                              (pillar mill person (Reliable) (Unreliable) (rgb 90 205 110) (rgb 245 150 40) 0.3)))
                (cond ((quiet? mill person) (list (item (Tile) at (Vec3 1.5 0.06 1.5) 0.0 (rgb 30 30 36))))
                      ((member? person (MillScreen-fresh screen)) (list (item (Tile) at (Vec3 1.5 0.06 1.5) 0.0 (rgb 235 205 70))))
                      (else (Nil))))))

    ;; The chosen person stands on a pale square, the one under the pointer
    ;; on a grey one.
    (: marker-items (-> MillScreen (List Item)))
    (define (marker-items screen)
      (let ((square-under (lambda (person size color)
                            (item (Tile) (Vec3 (Vec3-x (person-point person)) -0.02 (Vec3-z (person-point person)))
                                  (Vec3 size 0.05 size) 0.0 color))))
        (append (match (MillScreen-selected screen) ((Some person) (list (square-under person 1.7 (rgb 190 200 215)))) ((None) (Nil)))
                (match (MillScreen-hover screen) ((Some person) (list (square-under person 1.6 (rgb 90 98 112)))) ((None) (Nil))))))

    (: marker-version (-> MillScreen I32))
    (define (marker-version screen)
      (let ((code (lambda (choice) (match choice ((Some person) (+ person 1)) ((None) 0)))))
        (i64->i32 (+ (* 32 (code (MillScreen-selected screen))) (code (MillScreen-hover screen))))))

    (: view-mill-screen (-> MillScreen Frame))
    (define (view-mill-screen screen)
      (Frame camera sunlight (rgb 16 20 28) 1.0
             (list (Batch 0 0 (Solid) tie-items)
                   (Batch 1 (i64->i32 (MillScreen-version screen)) (Solid)
                          (lambda () (concatenate (map (lambda (person) (person-items screen person)) (iota person-count)))))
                   (Batch 2 (marker-version screen) (Solid) (lambda () (marker-items screen))))))

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
         (Cons (label "person" (look-text (MillScreen-mill screen) person))
               (map (lambda (tie) (button (string-append "choose-" (show tie)) (string-append "Choose " (first-name tie))
                                          (+ action-choose (i64->i32 tie))))
                    (neighbors person))))
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
      (string-append "Pillars: red dangerous, blue harmless (left); green reliable, orange unreliable (right)."
                     " Height is intensity. Yellow square: heard something new. Dark square: keeping quiet. Big: hub."))

    ;; `first` are panels to show before the screen's own.
    (: mill-screen-hud (-> MillScreen (List Panel) (List Panel)))
    (define (mill-screen-hud screen first)
      (let ((mill (MillScreen-mill screen)))
        (append first
                (list (Panel "status" (At (TopLeft) 0) (list (label "status" (lines (mill-status mill))) (label "message" (MillScreen-message screen))))
                      (Panel "person" (At (TopRight) 0) (person-widgets screen))
                      (Panel "actions" (At (BottomLeft) 0)
                             (if (mill-over? mill) (list (button "restart" "Restart" action-restart)) (action-buttons screen)))
                      (Panel "summary" (At (BottomRight) 0)
                             (map-indexed (lambda (index text) (label (string-append "summary-" (show index)) text))
                                          (append (MillScreen-summary screen) (list legend))))))))

    ))
