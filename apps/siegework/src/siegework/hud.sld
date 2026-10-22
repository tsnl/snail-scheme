;; The HUD: a dock one control wide on the side of the playing hand. Its
;; edge column holds the readouts and, while a cell is selected, the build
;; menu; the column beside it holds the menu and turning buttons and the
;; build queue. The nests and the clock sit in the opposite corner, with
;; notices beneath them: an alert while the colony is under attack, and why
;; the last order was refused. A title banner across the top says how to
;; begin, and dialogs cover the menu, its confirmations and the results.
;;
;; Only related controls share a panel. Every button names the command it
;; gives; one the world would reject is greyed out and explains why in its
;; help.
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

    ;; A button for `command`, enabled unless `rejection` says why not: one
    ;; that may work later is marked waiting, one that cannot apply here is
    ;; muted.
    (: command-button (-> Look String String Command (Option Rejection) Widget))
    (define (command-button look-of label caption command rejection)
      (let ((code (press-code command)))
        (match rejection
          ((Some why) (Button (Look-tone-set (Look-help-set look-of (rejection-text why)) (if (later? why) (Warning) (Muted)))
                              label caption (Pair-first code) (Pair-second code) (Disabled) -1.0))
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

    ;; Hub health, energy, the workers, and the strength of the nests with
    ;; the time to the next attack.
    (: readouts (-> Game Panel))
    (define (readouts game)
      (let* ((world (Game-world game)) (hub (World-hub world))
             (tier (difficulty-tier (threat-tick world))) (until (- (next-attack-tick (World-tick world)) (World-tick world))))
        (Panel "readouts" (At (side game) 0)
               (list (Dial (Look "health" "health" "Hub health" (if (< (* 10 (Hub-health hub)) (* 3 hub-health)) (Danger) (Good)) "")
                           (show (Hub-health hub)) (/ (i64->f32 (Hub-health hub)) (i64->f32 hub-health)))
                     (Dial (face "energy" "energy" "Energy stored in the network") (show (World-energy world))
                           (min 1.0 (/ (i64->f32 (World-energy world)) 400.0)))
                     (workers-dial world)
                     (Dial (Look "threat" "threat" (string-append "Strength " (show tier) "; next attack in " (seconds until))
                                 (if (< until 100) (Warning) (Plain)) (seconds until))
                           (string-append "T" (show tier)) (/ (i64->f32 (remainder (threat-tick world) difficulty-step)) (i64->f32 difficulty-step)))))))

    ;; The workers standing, ringed by their share of the most the colony
    ;; may have.
    (: workers-dial (-> World Widget))
    (define (workers-dial world)
      (let ((count (length (World-workers world))) (idle (length (filter (lambda (w) (match (Worker-job w) ((Some _) #f) ((None) #t))) (World-workers world)))))
        (Dial (face "workers" "worker" (string-append "Workers: " (show idle) " idle of " (show count) "; the hub trains up to " (show maximum-workers)))
              (show count) (/ (i64->f32 count) (i64->f32 maximum-workers)))))

    ;; The menu, or the results once the game is decided, then turning.
    (: controls (-> Game Panel))
    (define (controls game)
      (let ((decided (not (playing? (Game-world game)))))
        (Panel "controls" (At (side game) 1)
               (list (plain-button (face "pause" (if decided "results" "pause") (if decided "Results" "Pause")) "P" (if decided (ShowResults) (OpenMenu)))
                     (plain-button (face "turn-left" "turn-left" "Turn left") "Q" (Turn -1))
                     (plain-button (face "turn-right" "turn-right" "Turn right") "E" (Turn 1))))))

    ;; ---- Construction ----

    ;; The build menu is the same for every selected cell: a pylon, a
    ;; turret, an extractor, a wall, a portal, an upgrade, a rush and
    ;; closing. In the next column, under the menu and turning buttons,
    ;; come cancelling work and scavenging, or at the hub repair and a new
    ;; worker, so the dock fits short screens. Each is greyed out where it
    ;; does not apply.
    (: construction (-> Game (List Panel)))
    (define (construction game)
      (match (Game-selected game)
        ((Some cell) (list (Panel "construction" (At (side game) 0) (build-menu game cell))))
        ((None) (Nil))))

    (: upkeep (-> Game (List Panel)))
    (define (upkeep game)
      (match (Game-selected game)
        ((Some cell) (list (Panel "care" (At (side game) 1) (care game cell))))
        ((None) (Nil))))

    (: build-menu (-> Game Cell (List Widget)))
    (define (build-menu game cell)
      (list (build-button game cell (Pylon)) (build-button game cell (Turret)) (build-button game cell (Extractor)) (build-button game cell (Wall))
            (portal-button game cell) (upgrade-button game cell) (rush-button game cell) (plain-button (face "close" "close" "Close") "Esc" (CloseCard))))

    (: kind-icon (-> Kind String))
    (define (kind-icon kind)
      (match kind
        ((Extractor) "extractor")
        ((Pylon) "pylon")
        ((Turret) "turret")
        ((Wall) "wall")))

    (: kind-key (-> Kind String))
    (define (kind-key kind)
      (match kind
        ((Pylon) "1")
        ((Turret) "2")
        ((Extractor) "3")
        ((Wall) "4")))

    (: build-button (-> Game Cell Kind Widget))
    (define (build-button game cell kind)
      (let ((price (* (raise-cost kind 0) (if (Game-rush game) 5 1))))
        (command-button (Look (string-append "build-" (kind-icon kind)) (kind-icon kind)
                              (string-append (kind-name kind) ": " (show (quotient (raise-duration kind 0) 10)) "s to build")
                              (if (opening-move? (Game-world game) kind) (Suggested) (Plain)) "")
                        (kind-key kind) (show price) (BuildAt kind cell) (check (Game-world game) (Build kind cell (Game-rush game))))))

    ;; Making the selected pylon a portal.
    (: portal-button (-> Game Cell Widget))
    (define (portal-button game cell)
      (command-button (face "portal" "portal" (string-append "Portal: workers jump between powered portals and the hub; "
                                                             (show (quotient portal-duration 10)) "s to build"))
                      "5" (show portal-cost) (PortalAt cell) (check (Game-world game) (MakePortal cell))))

    ;; What the next level of the selected building costs.
    (: upgrade-button (-> Game Cell Widget))
    (define (upgrade-button game cell)
      (command-button (face "upgrade" "upgrade" "Upgrade") "U" (match (upgrade-cost (Game-world game) cell) ((Some cost) (show cost)) ((None) ""))
                      (UpgradeAt cell) (check (Game-world game) (Upgrade cell))))

    (: upgrade-cost (-> World Cell (Option I64)))
    (define (upgrade-cost world cell)
      (if (hub-cell? (World-hub world) cell)
          (None)
          (match (building-at world cell)
            ((Some b) (if (and (built? b) (< (Building-level b) maximum-level)) (Some (raise-cost (Building-kind b) (Building-level b))) (None)))
            ((None) (None)))))

    ;; Work on the selected cell is rushed to its end; otherwise the button
    ;; makes new buildings rushed.
    (: rush-button (-> Game Cell Widget))
    (define (rush-button game cell)
      (match (cell-work (Game-world game) cell #f)
        ((Some work) (command-button (face "rush" "rush" "Rush: finish the work now") "R" (show (rush-price work)) (RushAt cell) (check (Game-world game) (Rush cell))))
        ((None) (toggle-button (face "rush-orders" "rush" "Rush new buildings: ready at once for five times the price") "R" "×5" (ToggleRush) (Game-rush game)))))

    ;; The work an order on the cell changes: a building's, or at the hub
    ;; its newest work for cancelling and its oldest for rushing.
    (: cell-work (-> World Cell Bool (Option Work)))
    (define (cell-work world cell newest)
      (match (if (hub-cell? (World-hub world) cell)
                 (owner-work world (OfHub) newest)
                 (match (building-at world cell)
                   ((Some b) (owner-work world (OfBuilding b) newest))
                   ((None) (None))))
        ((Some (Pair owner work)) (Some work))
        ((None) (None))))

    ;; Cancelling, greyed out while nothing is being built, then scavenging,
    ;; or at the hub repair and training a worker.
    (: care (-> Game Cell (List Widget)))
    (define (care game cell)
      (Cons (cancel-button game cell)
            (if (hub-cell? (World-hub (Game-world game)) cell) (list (repair-button game) (worker-button game)) (list (scavenge-button game cell)))))

    (: cancel-button (-> Game Cell Widget))
    (define (cancel-button game cell)
      (command-button (face "cancel" "cancel" "Cancel the work and refund it") "C"
                      (match (cell-work (Game-world game) cell #t) ((Some w) (string-append "+" (show (work-refund w)))) ((None) ""))
                      (CancelAt cell) (check (Game-world game) (Cancel cell))))

    (: scavenge-button (-> Game Cell Widget))
    (define (scavenge-button game cell)
      (command-button (face "scavenge" "scavenge" "Scavenge: remove it for a fifth of its cost, or half for a wall") "X"
                      (match (building-at (Game-world game) cell) ((Some b) (string-append "+" (show (scavenge-refund b)))) ((None) ""))
                      (ScavengeAt cell) (check (Game-world game) (Scavenge cell))))

    (: repair-button (-> Game Widget))
    (define (repair-button game)
      (let ((world (Game-world game)))
        (command-button (face "repair" "repair" "Repair the hub to full health; a worker takes 2s") "F" (show (repair-price (World-hub world))) (RepairHub) (check world (Repair)))))

    (: worker-button (-> Game Widget))
    (define (worker-button game)
      (command-button (face "build-worker" "worker" (string-append "Build worker: " (show (quotient worker-duration 10)) "s at the hub"))
                      "B" (show worker-cost) (TrainWorker) (check (Game-world game) (Train))))

    ;; ---- Queue ----

    ;; The works in order: a ring for each in progress, and ! and dimmed
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
        (Button (Look (string-append "queue-" (show index)) (task-icon task) (task-help task) (if (Task-supplied task) (Plain) (Muted)) (if (Task-supplied task) "" "!"))
                "" "" (Pair-first code) (Pair-second code) (Enabled)
                (if (Task-active task) (/ (i64->f32 (Work-progress work)) (i64->f32 (Work-duration work))) -1.0))))

    (: task-cell (-> World Task Cell))
    (define (task-cell world task)
      (match (Task-owner task)
        ((OfBuilding b) (Building-cell b))
        (_ (Hub-cell (World-hub world)))))

    (: task-icon (-> Task String))
    (define (task-icon task)
      (match (Task-owner task)
        ((OfHub) "repair")
        ((OfTraining _) "worker")
        ((OfBuilding b) (cond ((linking? task) "portal") ((built? b) "upgrade") (else (kind-icon (Building-kind b)))))))

    (: linking? (-> Task Bool))
    (define (linking? task)
      (match (Work-labor (Task-work task))
        ((Linking) #t)
        (_ #f)))

    (: task-help (-> Task String))
    (define (task-help task)
      (string-append (match (Task-owner task)
                       ((OfHub) "Hub repair")
                       ((OfTraining _) "Worker")
                       ((OfBuilding b) (string-append (kind-name (Building-kind b)) (cond ((linking? task) " portal") ((built? b) " upgrade") (else "")))))
                     (cond ((not (Task-supplied task)) ", unpowered")
                           ((Task-active task) ", building")
                           ((needs-worker? (Work-labor (Task-work task))) ", waiting for a worker")
                           (else ", waiting"))))

    ;; ---- Opening ----

    ;; Until the first extractor is built, the world waits under a title
    ;; banner that points to the glowing crystals, then, once one is
    ;; selected, to the build button the menu suggests. It links to the
    ;; guide.
    (: opening (-> Game (List Panel)))
    (define (opening game)
      (if (opening? (Game-world game))
          (list (Panel "opening" (Banner)
                       (list (text "opening-title" "Siegework")
                             (opening-step game)
                             (Link (face "how-to-play" "" "The rules and controls") "How to play" guide-url))))
          (Nil)))

    ;; The step points to the glowing crystals, then to the build button;
    ;; each step's key lets the page color its strong words.
    (: opening-step (-> Game Widget))
    (define (opening-step game)
      (if (extractor-offered? game)
          (Text (look "opening-build") (list (Normal "Click the ") (Strong "build button") (Normal " to continue")))
          (Text (look "opening-crystal") (list (Normal "Click the ") (Strong "glowing crystal")))))

    ;; The guide ships beside the game, so it always describes the rules
    ;; this build plays by.
    (: guide-url String)
    (define guide-url "./guide.html")

    ;; Whether the selected cell would take an extractor now.
    (: extractor-offered? (-> Game Bool))
    (define (extractor-offered? game)
      (match (Game-selected game)
        ((Some cell) (match (check (Game-world game) (Build (Extractor) cell (Game-rush game))) ((Some _) #f) ((None) #t)))
        ((None) #f)))

    (: opening? (-> World Bool))
    (define (opening? world)
      (and (not (World-started world)) (playing? world)))

    (: opening-move? (-> World Kind Bool))
    (define (opening-move? world kind)
      (and (opening? world) (match kind ((Extractor) #t) (_ #f))))

    ;; ---- Objective ----

    ;; A star for each nest, filled once destroyed, and the time in play.
    (: objective (-> Game Panel))
    (define (objective game)
      (let ((world (Game-world game)))
        (Panel "objective" (At (far-side game) 0)
               (list (text "nests" (list->string (map (lambda (nest) (if (= (Nest-health nest) 0) #\★ #\☆)) (World-nests world))))
                     (text "elapsed" (clock-text (World-tick world)))))))

    ;; ---- Notices ----

    ;; Under the nests, away from the dock so they never move the controls:
    ;; an alert while the colony was struck in the last eight seconds, which
    ;; goes to the latest attack, then, while a cell is selected, why the
    ;; last order on it was refused.
    (: notices (-> Game (List Panel)))
    (define (notices game)
      (append (attack-alert game) (refusal game)))

    (: attack-alert (-> Game (List Panel)))
    (define (attack-alert game)
      (let ((world (Game-world game)))
        (match (find (lambda (a) (< (- (World-tick world) (Alert-tick a)) 80)) (World-alerts world))
          ((Some alert) (list (Panel "alert" (At (far-side game) 0)
                                     (list (plain-button (Look "attack" "danger" "Under attack: go there" (Danger) "") "" (Locate (Alert-cell alert)))))))
          ((None) (Nil)))))

    (: refusal (-> Game (List Panel)))
    (define (refusal game)
      (match (Game-selected game)
        ((Some _) (if (string=? (Game-message game) "")
                      (Nil)
                      (list (Panel "message" (At (far-side game) 0) (list (Label (Look "message" "" "" (Danger) "") (Game-message game)))))))
        ((None) (Nil))))

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
                                              (string-append "Workers " (show (length (World-workers world))))
                                              (string-append "Nests destroyed " (show (- 3 (length (living-nests world)))) " of 3")
                                              (string-append "Map " (show (World-seed world)) ", " (biome-name (Land-biome (World-land world)))))
                                        "\n"))
                     (plain-button (face "inspect" "" "Look over the map") "Map" (InspectMap))
                     (plain-button (face "new-map" "" "Start a new map") "New map" (NewMap))))))

    ;; ---- HUD ----

    (: game-hud (-> Game (List Panel)))
    (define (game-hud game)
      (concatenate (list (list (readouts game)) (construction game) (list (controls game)) (upkeep game) (queue game) (list (objective game)) (notices game) (opening game)
                         (dialogs game))))

    ))
