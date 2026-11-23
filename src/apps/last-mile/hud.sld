;; Build the instrument panel once. Only the six changing readouts and
;; the two map markers cross the DOM boundary on subsequent updates.
(define-library (apps last-mile hud)
  (export Hud make-hud show!)
  (import
   (snail core base)
   (snail shell dom)
   (snail shell math)
   (snail shell game physics)
   (apps last-mile game)
   (apps last-mile district))
  (begin
    (record Hud
      ((stage Node)
       (title Node)
       (message Node)
       (signal Node)
       (mode Node)
       (range Node)
       (you Node)
       (goal Node)))

    (define (element (d Dom) (parent Node) (tag String) (class String) (text String)) (→ Node)
      (let ((n ((● d create-element) tag)))
        ((● d set-attribute) n "class" class)
        (unless (string=? text "") ((● d set-text) n text))
        ((● d insert-node) parent n (None)) n))

    (define (percent (n F64)) (→ String) (string-append (show (f64->i64 (round (* n 100.0)))) "%"))

    ;; World bounds mapped into the instrument’s width and height.
    (define (map-at (p XZ)) (→ String)
      (string-append "left:" (percent (/ (+ (● p x) 45.0) 90.0)) ";top:"
                     (percent (/ (+ (● p z) 55.0) 99.0)) ";"))

    (define (block! (d Dom) (map-node Node) (b Building)) (→ Unit)
      (let ((n (element d map-node "i" "block" "")))
        ((● d set-attribute) n "style" (string-append (map-at (● b center))
                                                      "width:"
                                                      (percent (/ (● b width) 90.0))
                                                      ";height:"
                                                      (percent (/ (● b depth) 99.0))
                                                      ";"))))

    (define (make-hud (d Dom)) (→ Hud)
      (let* ((root ((● d document-root))) (mast (element d root "header" "mast" ""))
             (map-box (element d root "aside" "radar" ""))
             (map-node (element d map-box "div" "map" ""))
             (card (element d root "section" "dispatch" ""))
             (dash (element d root "aside" "dash" "")))
        (element d mast "span" "eyebrow" "MERCER STREET PICTURES")
        (element d mast "h1" "" "LAST MILE")
        (element d map-box "span" "map-caption" "MERCER ST   /   N ↑")
        (for-each (lambda (b) (block! d map-node b)) buildings)
        (let* ((stage (element d card "div" "stage" "")) (title (element d card "h2" "" ""))
               (message (element d card "p" "" "")) (mode (element d dash "strong" "mode" ""))
               (range (element d dash "div" "range" ""))
               (signal (element d dash "span" "signal" "")))
          (new Hud
            (stage stage)
            (title title)
            (message message)
            (mode mode)
            (range range)
            (signal signal)
            (you (element d map-node "i" "you" "")) (goal (element d map-node "i" "goal" ""))))))

    (define (brief (w World) (seated Bool)) (→ (List String))
      (match (● w mission)
        ((Pickup) (list "PICTURE CAR" "Pick up Rosa’s sedan."
                        "One street permit, one last take. Press E beside the car, then drive north on Mercer."))
        ((Action) (list "ON LOCATION" "Hit the red prop plate."
                        "Point the car or your character at the square in front of the gate. Fire the paint marker within 22 m."))
        ((ToEditor) (list "CUTTING ROOM" "Deliver the film can."
                          (if seated
                              "Follow the gold marker to the editor’s table. Brake to a stop and press E to get out."
                              "Walk to the editor’s table and press E to hand over the can.")))
        ((Wrapped) (list "THAT’S A WRAP" "The last take is in."
                         "Rosa threads the reel. The gate falls right on cue. Keep exploring, or press R for another take."))))

    (define (bearing (b Body) (target XZ)) (→ String)
      (let ((turn (- (heading-to (● b position) target) (● b heading))))
        (cond ((< (cos turn) -0.6) "behind")
              ((> (sin turn) 0.4) "right")
              ((< (sin turn) -0.4) "left")
              (else "ahead"))))

    (define (show! (d Dom) (h Hud) (w World) (paused Bool)) (→ Unit)
      (let* ((b (carrier w)) (p (● b position)) (target (objective w))
             (seated (match (● w seat) ((OnFoot _) #f) (_ #t))) (lines (brief w seated))
             (speed (distance (● b velocity) (xz 0.0 0.0))) (tell (● d set-text)))
        (tell (● h stage) (list-ref lines 0))
        (tell (● h title) (list-ref lines 1))
        (tell (● h message) (list-ref lines 2))
        (tell (● h signal) (cond (paused "PAUSED   /   P TO RESUME")
                                 ((> (● w cooldown) 0) "MARKER CYCLING")
                                 (else "MARKER READY")))
        (tell (● h mode)
              (match (● w seat)
                ((Driving) (string-append (show (f64->i64 (round (* 3.6 speed)))) " KM/H"))
                (_ "ON FOOT")))
        (tell (● h range)
              (string-append (show (f64->i64 (round (distance p target))))
                             " m  ·  "
                             (bearing b target)))
        ((● d set-attribute) (● h you) "style" (map-at p))
        ((● d set-attribute) (● h goal) "style" (map-at target))))))
