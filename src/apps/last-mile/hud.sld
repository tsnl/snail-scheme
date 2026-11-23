;; Build the instruments once. Dialogue comes from the saved story cursor.
(define-library (apps last-mile hud)
  (export Hud make-hud show!)
  (import
   (snail core base)
   (snail shell dom)
   (snail shell math)
   (snail shell game physics)
   (snail shell game boarding)
   (snail shell game dialogue)
   (apps last-mile lines)
   (apps last-mile game)
   (apps last-mile district))
  (begin
    (record Hud
      ((stage Node)
       (title Node)
       (message Node)
       (speech Node)
       (answers Node)
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
            (speech (element d card "p" "speech" ""))
            (answers (element d card "div" "answers" ""))
            (mode mode)
            (range range)
            (signal signal)
            (you (element d map-node "i" "you" "")) (goal (element d map-node "i" "goal" ""))))))

    (define (brief (w Game)) (→ (List String))
      (match (● w mission)
        ((PictureCar)
         (list "PICTURE CAR"
               "Pick up the sedan."
               "Press E near the car to walk to the driver’s door."))
        ((MeetRosa) (list "PASSENGER PICKUP" "Pull over for Rosa." (match (● w rosa)
                                                                     ((AtDoor _)
                                                                      (if (blocked-door? w
                                                                                         (PassengerDoor))
                                                                          "Rosa’s door is blocked. Pull forward or back and brake again."
                                                                          "Hold the brake. Rosa is walking to the passenger door."))
                                                                     ((Entering _ _)
                                                                      "Rosa is getting in. Hold the brake.")
                                                                     (_
                                                                      "Drive north to the gold diamond. Hold B and leave room at the passenger door."))))
        ((FindMark)
         (list "SHOOTING MARK"
               "Make the right on Mercer."
               "Turn before the delivery van. Stop on the gold tape facing the red plate."))
        ((OnCue)
         (list "ACTION"
               "Hit the red prop plate."
               "Rosa calls action. Aim at the plate and fire the paint marker."))
        ((ToCuttingRoom)
         (list "CUTTING ROOM"
               "Drive Rosa to the editor."
               "Take the next left. Brake at the editor’s table with room on Rosa’s side."))
        ((HandOff)
         (list "HANDOFF"
               "Rosa has the reel."
               (if (and (aboard? (● w rosa)) (blocked-door? w (PassengerDoor)))
                   "The passenger door is blocked. Reposition near the table and brake again."
                   "Keep the sedan stopped near the table while Rosa delivers the reel.")))
        ((Finished)
         (list "THAT’S A WRAP"
               "The last take is in."
               "The reel is on the editor’s table. Keep exploring or press R for another take."))))
    (define (show-dialogue! (d Dom) (h Hud) (at (Option Cursor))) (→ Unit)
      (let ((tell (● d set-text)))
        (match at
          ((None) (tell (● h speech) "") (tell (● h answers) ""))
          ((Some c) (tell (● h speech) (spoken conversation c))
           (let ((options (replies conversation c)))
             (tell (● h answers)
                   (if (null? options) "T  ·  Continue"
                       (string-join (map-indexed (lambda (i reply)
                                                   (string-append (show (+ 1 i))
                                                                  "  ·  "
                                                                  (● reply text)))
                                                 options)
                                    "\n"))))))))
    (define (bearing (b Body) (target XZ)) (→ String)
      (let ((turn (- (heading-to (● b position) target) (● b heading))))
        (cond ((< (cos turn) -0.6) "behind")
              ((> (sin turn) 0.4) "right")
              ((< (sin turn) -0.4) "left")
              (else "ahead"))))

    (define (show! (d Dom) (h Hud) (w Game) (paused Bool)) (→ Unit)
      (let* ((b (carrier w)) (p (● b position)) (target (objective w))
             (lines (brief w))
             (speed (distance (● b velocity) (xz 0.0 0.0))) (tell (● d set-text)))
        (show-dialogue! d h (● w talk))
        (tell (● h stage) (list-ref lines 0))
        (tell (● h title) (list-ref lines 1))
        (tell (● h message) (list-ref lines 2))
        (tell (● h signal) (cond (paused "PAUSED   /   P TO RESUME")
                                 ((> (● w cooldown) 0) "MARKER CYCLING")
                                 (else "MARKER READY")))
        (tell (● h mode)
              (match (● w driver)
                ((AtDoor _) "AT DRIVER’S DOOR")
                ((Entering _ _) "BOARDING")
                ((Leaving _) "STEPPING OUT")
                ((Aboard) (string-append (show (f64->i64 (round (* 3.6 speed)))) " KM/H"))
                (_ "ON FOOT")))
        (tell (● h range)
              (string-append (show (f64->i64 (round (distance p target))))
                             " m  ·  "
                             (bearing b target)))
        ((● d set-attribute) (● h you) "style" (map-at p))
        ((● d set-attribute) (● h goal) "style" (map-at target))))))
