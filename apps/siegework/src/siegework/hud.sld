;; The HUD, laid out as in the original Siegework: an edge dock of round
;; readouts and controls on the side of the playing hand, the card of
;; actions for the selected cell below it, the build queue and attack alerts
;; beside it, the nests and the clock in the opposite corner, and dialogs for
;; the menu, its confirmations and the results.
;;
;; Every button names the command it gives; buttons that would be rejected
;; are disabled and explain why in their help.
(define-library (siegework hud)
  (export
   game-hud)
  (import
   (lofi base)
   (lofi app)
   (siegework grid)
   (siegework terrain)
   (siegework world)
   (siegework colony)
   (siegework siege)
   (siegework game))
  (begin

    ;; ---- Widgets ----

    (: face (-> String String String Look))
    (define (face key icon help)
      (Look key icon help (Plain) ""))

    (: text (-> String String Widget))
    (define (text key words)
      (Label (look key) words))

    ;; A button for `command`, enabled unless `rejection` says why not.
    (: command-button (-> Look String String Command (Option Rejection) Widget))
    (define (command-button look-of label caption command rejection)
      (let ((code (press-code command)))
        (match rejection
          ((Some why) (Button (Look-help-set look-of (rejection-text why)) label caption (Pair-first code) (Pair-second code) (Disabled) -1.0))
          ((None) (Button look-of label caption (Pair-first code) (Pair-second code) (Enabled) -1.0)))))

    (: plain-button (-> Look String Command Widget))
    (define (plain-button look-of label command)
      (command-button look-of label "" command (None)))

    (: toggle-button (-> Look String String Command Bool Widget))
    (define (toggle-button look-of label caption command on)
      (let ((code (press-code command)))
        (Button look-of label caption (Pair-first code) (Pair-second code) (if on (Selected) (Enabled)) -1.0)))

    (: side (-> Game Corner))
    (define (side game)
      (if (Game-left-handed game) (TopLeft) (TopRight)))

    (: far-side (-> Game Corner))
    (define (far-side game)
      (if (Game-left-handed game) (TopRight) (TopLeft)))

    (: seconds (-> I64 String))
    (define (seconds ticks)
      (string-append (show (quotient (+ ticks 9) 10)) "s"))

    (: clock-text (-> I64 String))
    (define (clock-text ticks)
      (let ((total (quotient ticks 10)))
        (string-append (show (quotient total 60)) ":" (if (< (remainder total 60) 10) "0" "") (show (remainder total 60)))))

    ;; ---- Dock ----

    ;; Energy, hub health, busy build slots, and the strength of the nests
    ;; with the time to the next attack.
    (: readouts (-> Game Panel))
    (define (readouts game)
      (let* ((world (Game-world game)) (hub (World-hub world)) (busy (length (filter Task-active (tasks world))))
             (tier (difficulty-tier (threat-tick world))) (until (- (next-attack-tick (World-tick world)) (World-tick world))))
        (Panel "readouts" (At (side game) 0)
               (list (Dial (face "energy" "energy" "Energy stored in the network") (show (World-energy world))
                           (min 1.0 (/ (i64->f32 (World-energy world)) 400.0)))
                     (Dial (Look "health" "health" "Hub health" (if (< (* 10 (Hub-health hub)) (* 3 hub-health)) (Danger) (Good)) "")
                           (show (Hub-health hub)) (/ (i64->f32 (Hub-health hub)) (i64->f32 hub-health)))
                     (Dial (face "slots" "slots" "Build slots working") (string-append (show busy) "/" (show (Hub-slots hub)))
                           (/ (i64->f32 busy) (i64->f32 (Hub-slots hub))))
                     (Dial (Look "threat" "threat" (string-append "Strength " (show tier) "; next attack in " (seconds until))
                                 (if (< until 100) (Warning) (Plain)) (seconds until))
                           (string-append "T" (show tier)) (/ (i64->f32 (remainder (threat-tick world) difficulty-step)) (i64->f32 difficulty-step)))))))

    (: controls (-> Game Panel))
    (define (controls game)
      (let ((decided (not (playing? (Game-world game)))))
        (Panel "controls" (At (side game) 0)
               (list (plain-button (face "home" "home" "Return to the hub") "H" (Home))
                     (plain-button (face "pause" (if decided "results" "pause") (if decided "Results" "Pause")) (if decided "R" "P")
                                   (if decided (ShowResults) (OpenMenu)))
                     (plain-button (face "turn-left" "turn-left" "Turn left") "Q" (Turn -1))
                     (plain-button (face "turn-right" "turn-right" "Turn right") "E" (Turn 1))))))

    ;; ---- Card ----

    ;; What can be done on the selected cell, with the last rejection.
    (: card (-> Game (List Panel)))
    (define (card game)
      (match (Game-selected game)
        ((Some cell) (list (Panel "card" (At (side game) 0)
                                  (append (card-widgets game cell)
                                          (append (if (string=? (Game-message game) "") (Nil)
                                                      (list (Label (Look "message" "" "" (Danger) "") (Game-message game))))
                                                  (list (plain-button (face "close" "close" "Close") "Esc" (CloseCard))))))))
        ((None) (Nil))))

    (: card-widgets (-> Game Cell (List Widget)))
    (define (card-widgets game cell)
      (let ((world (Game-world game)))
        (cond ((hub-cell? (World-hub world) cell) (hub-card game cell))
              (else (match (building-at world cell)
                      ((Some b) (building-card game b))
                      ((None) (ground-card game cell)))))))

    (: kind-icon (-> Kind String))
    (define (kind-icon kind)
      (match kind
        ((Extractor) "extractor")
        ((Pylon) "pylon")
        ((Turret) "turret")))

    ;; An extractor takes the turret's key on a crystal.
    (: kind-key (-> Kind String))
    (define (kind-key kind)
      (match kind
        ((Pylon) "1")
        ((Turret) "2")
        ((Extractor) "2")))

    ;; Building choices: an extractor on a crystal, a pylon or turret
    ;; elsewhere. The rush toggle shows what rushing adds.
    (: ground-card (-> Game Cell (List Widget)))
    (define (ground-card game cell)
      (let* ((world (Game-world game)) (crystal (crystal-at world cell)) (kinds (match crystal ((Some _) (list (Extractor))) ((None) (list (Pylon) (Turret))))))
        (Cons (text "title" (ground-title world cell crystal))
              (if (explored? world cell)
                  (append (map (lambda (kind) (build-button game cell kind)) kinds)
                          (list (toggle-button (face "rush-orders" "rush" "Rush new buildings: ready at once for five times the price") "R" "×5" (ToggleRush) (Game-rush game))))
                  (Nil)))))

    (: ground-title (-> World Cell (Option Crystal) String))
    (define (ground-title world cell crystal)
      (cond ((not (explored? world cell)) "Unexplored")
            (else (match crystal
                    ((Some c) (string-append "Crystal · " (show (Crystal-reserve c)) " energy"))
                    ((None) (match (ground-at (World-land world) cell)
                              ((Grass) "Grass")
                              ((Water) "Water")
                              ((Rock) (if (opened? world cell) "Dug rock" "Rock"))))))))

    (: build-button (-> Game Cell Kind Widget))
    (define (build-button game cell kind)
      (let ((price (* (raise-cost kind 0) (if (Game-rush game) 5 1))))
        (command-button (face (string-append "build-" (kind-icon kind)) (kind-icon kind)
                              (string-append (kind-name kind) ": " (show (quotient (raise-duration kind 0) 10)) "s to build"))
                        (kind-key kind) (show price) (BuildAt kind cell) (check (Game-world game) (Build kind cell (Game-rush game))))))

    ;; A building's upgrade, scavenging, and the rush and cancellation of
    ;; its work.
    (: building-card (-> Game Building (List Widget)))
    (define (building-card game b)
      (let ((world (Game-world game)) (cell (Building-cell b)))
        (Cons (text "title" (building-title world b))
              (append (if (built? b) (list (upgrade-button game cell (if (< (Building-level b) maximum-level) (raise-cost (Building-kind b) (Building-level b)) 0))) (Nil))
                      (append (work-buttons game cell (Building-work b))
                              (if (built? b)
                                  (list (command-button (face "scavenge" "scavenge" "Scavenge: remove it for a fifth of its cost") "X"
                                                        (string-append "+" (show (quotient (invested b) 5))) (ScavengeAt cell) (check world (Scavenge cell))))
                                  (Nil)))))))

    (: building-title (-> World Building String))
    (define (building-title world b)
      (string-append (kind-name (Building-kind b)) (if (built? b) (string-append " " (show (Building-level b))) " site")
                     " · " (show (Building-health b)) " health" (if (or (not (built? b)) (powered? world (Building-id b))) "" " · unpowered")))

    (: upgrade-button (-> Game Cell I64 Widget))
    (define (upgrade-button game cell cost)
      (command-button (face "upgrade" "upgrade" "Upgrade") "U" (if (= cost 0) "max" (show cost)) (UpgradeAt cell) (check (Game-world game) (Upgrade cell))))

    (: work-buttons (-> Game Cell (Option Work) (List Widget)))
    (define (work-buttons game cell work)
      (match work
        ((Some w) (list (command-button (face "rush" "rush" "Rush: finish the work now") "R" (show (rush-price w)) (RushAt cell) (check (Game-world game) (Rush cell)))
                        (command-button (face "cancel" "cancel" "Cancel the work and refund it") "C" (string-append "+" (show (work-refund w)))
                                        (CancelAt cell) (None))))
        ((None) (Nil))))

    ;; The hub's build slots, repair, and the rush and cancellation of a new
    ;; slot.
    (: hub-card (-> Game Cell (List Widget)))
    (define (hub-card game cell)
      (let* ((world (Game-world game)) (hub (World-hub world)) (missing (- hub-health (Hub-health hub))))
        (Cons (text "title" (string-append "Hub · " (show (Hub-health hub)) " health · " (show (Hub-slots hub)) " build slots"))
              (append (list (upgrade-button game cell (if (< (Hub-slots hub) maximum-slots) (slot-cost (Hub-slots hub)) 0)))
                      (append (work-buttons game cell (Hub-work hub))
                              (list (command-button (face "repair" "repair" "Repair: two health per energy") "F" (show (quotient (+ missing 1) 2))
                                                    (RepairHub) (check world (Repair)))))))))

    ;; ---- Queue and alerts ----

    ;; The works in order: a ring for each holding a slot, and ! and dimmed
    ;; when unpowered. Tapping one goes to it.
    (: queue (-> Game (List Panel)))
    (define (queue game)
      (let* ((world (Game-world game)) (all (tasks world)) (shown (take all 6)))
        (if (null? all)
            (Nil)
            (list (Panel "queue" (At (side game) 1)
                         (append (map-indexed (lambda (index task) (queue-chip world index task)) shown)
                                 (if (> (length all) 6) (list (text "queue-more" (string-append "+" (show (- (length all) 6))))) (Nil))))))))

    (: queue-chip (-> World I64 Task Widget))
    (define (queue-chip world index task)
      (let* ((work (Task-work task)) (cell (task-cell world task)) (code (press-code (Locate cell))))
        (Button (Look (string-append "queue-" (show index)) (task-icon task) (task-help task)
                      (if (Task-supplied task) (Plain) (Muted)) (if (Task-supplied task) "" "!"))
                "" "" (Pair-first code) (Pair-second code) (Enabled)
                (if (Task-active task) (/ (i64->f32 (Work-progress work)) (i64->f32 (Work-duration work))) -1.0))))

    (: task-cell (-> World Task Cell))
    (define (task-cell world task)
      (match (Task-owner task)
        ((OfHub) (Hub-cell (World-hub world)))
        ((OfBuilding b) (Building-cell b))))

    (: task-icon (-> Task String))
    (define (task-icon task)
      (match (Task-owner task)
        ((OfHub) "slots")
        ((OfBuilding b) (if (built? b) "upgrade" (kind-icon (Building-kind b))))))

    (: task-help (-> Task String))
    (define (task-help task)
      (string-append (match (Task-owner task)
                       ((OfHub) "Build slot")
                       ((OfBuilding b) (string-append (kind-name (Building-kind b)) (if (built? b) " upgrade" ""))))
                     (cond ((not (Task-supplied task)) ", unpowered") ((Task-active task) ", building") (else ", waiting"))))

    ;; Where the colony was struck lately: tap to go there, or silence it.
    (: alerts (-> Game (List Panel)))
    (define (alerts game)
      (let* ((world (Game-world game))
             (shown (filter (lambda (a) (and (< (- (World-tick world) (Alert-tick a)) 80) (not (alert-muted? game a)))) (World-alerts world))))
        (if (null? shown)
            (Nil)
            (list (Panel "alerts" (At (side game) 1) (concatenate (map alert-widgets shown)))))))

    (: alert-widgets (-> Alert (List Widget)))
    (define (alert-widgets alert)
      (let ((index (show (cell-index (Alert-cell alert)))))
        (list (plain-button (Look (string-append "alert-" index) "danger" "Go to the attack" (Danger) "") "Attack" (Locate (Alert-cell alert)))
              (plain-button (Look (string-append "silence-" index) "close" "Silence alerts here for eight seconds" (Danger) "") "" (Silence (Alert-cell alert))))))

    ;; ---- Objective ----

    ;; A star for each nest, filled once destroyed, and the time in play.
    (: objective (-> Game Panel))
    (define (objective game)
      (let ((world (Game-world game)))
        (Panel "objective" (At (far-side game) 0)
               (list (text "nests" (list->string (map (lambda (nest) (if (= (Nest-health nest) 0) #\★ #\☆)) (World-nests world))))
                     (text "elapsed" (clock-text (World-tick world)))))))

    ;; ---- Dialogs ----

    (: dialogs (-> Game (List Panel)))
    (define (dialogs game)
      (match (Game-menu game)
        ((Closed) (Nil))
        ((Paused) (list (pause-dialog game)))
        ((Restarting) (list (confirm-dialog "restart" "Restart on a new map?" "Restart" (NewMap))))
        ((Resigning) (list (confirm-dialog "resign" "Resign this colony? The map is revealed." "Resign" (ConfirmResign))))
        ((Results) (list (results-dialog game)))))

    (: pause-dialog (-> Game Panel))
    (define (pause-dialog game)
      (Panel "pause" (Dialog (Pair-first (press-code (Resume))))
             (list (text "pause-title" "Paused")
                   (plain-button (face "resume" "" "Resume") "Resume" (Resume))
                   (plain-button (face "restart" "" "Restart on a new map") "Restart…" (AskRestart))
                   (plain-button (face "resign" "" "Resign this colony") "Resign…" (AskResign))
                   (toggle-button (face "right-handed" "" "Controls on the right") "Right-handed" "" (Hand #f) (not (Game-left-handed game)))
                   (toggle-button (face "left-handed" "" "Controls on the left") "Left-handed" "" (Hand #t) (Game-left-handed game)))))

    (: confirm-dialog (-> String String String Command Panel))
    (define (confirm-dialog key question label command)
      (Panel key (Dialog (Pair-first (press-code (OpenMenu))))
             (list (text (string-append key "-title") question)
                   (plain-button (Look (string-append "accept-" key) "" question (Danger) "") label command)
                   (plain-button (face "back" "" "Back to the menu") "Back" (OpenMenu)))))

    ;; Time, combat, energy, buildings, nests and the seed, from the world.
    (: results-dialog (-> Game Panel))
    (define (results-dialog game)
      (let* ((world (Game-world game)) (ledger (World-ledger world)))
        (Panel "results" (Dialog (Pair-first (press-code (InspectMap))))
               (list (text "results-title" (match (World-outcome world) ((Won) "Victory") ((Lost) "Defeat") ((Resigned) "Resigned") ((Playing) "In play")))
                     (text "results-statistics"
                           (string-join (list (string-append "Time " (clock-text (World-tick world)))
                                              (string-append "Enemies destroyed " (show (Ledger-kills ledger)))
                                              (string-append "Energy produced " (show (Ledger-produced ledger)) ", spent " (show (Ledger-spent ledger)))
                                              (string-append "Buildings standing " (show (length (filter built? (World-buildings world)))) ", lost " (show (Ledger-lost ledger)))
                                              (string-append "Nests destroyed " (show (- 3 (length (living-nests world)))) " of 3")
                                              (string-append "Map " (show (World-seed world))))
                                        "\n"))
                     (plain-button (face "inspect" "" "Look over the map") "Map" (InspectMap))
                     (plain-button (face "new-map" "" "Start a new map") "New map" (NewMap))))))

    ;; ---- HUD ----

    (: game-hud (-> Game (List Panel)))
    (define (game-hud game)
      (concatenate (list (list (readouts game) (controls game)) (card game) (queue game) (alerts game) (list (objective game)) (dialogs game))))

    ))
