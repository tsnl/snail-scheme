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
   (snail core base)
   (snail shell app)
   (siegework grid)
   (siegework terrain)
   (siegework world)
   (siegework colony)
   (siegework siege)
   (siegework game))
  (begin

    ;; ---- Widgets ----

    (define (face (key String) (icon String) (help String)) (→ Look)
      (Look key icon help (Plain) ""))

    ;; A button for `command`, enabled unless `rejection` says why not: one
    ;; that may work later is marked waiting, one that cannot apply here is
    ;; muted.
    (define (command-button (look-of Look)
                            (text String)
                            (caption String)
                            (command Command)
                            (rejection (Option Rejection)))
      (→ Widget)
      (let ((code (press-code command)))
        (match rejection
          ((Some why)
           (Button (Look-tone-set (Look-help-set look-of (rejection-text why))
                                  (if (later? why) (Warning) (Muted)))
                   text caption (● code first) (● code second) (Disabled) -1.0))
          ((None)
           (Button look-of text caption (● code first) (● code second) (Enabled) -1.0)))))

    (define (plain-button (look-of Look) (text String) (command Command)) (→ Widget)
      (command-button look-of text "" command (None)))

    (define (toggle-button (look-of Look)
                           (text String)
                           (caption String)
                           (command Command)
                           (on Bool))
      (→ Widget)
      (let ((code (press-code command)))
        (Button look-of
                text
                caption
                (● code first)
                (● code second)
                (if on (Selected) (Enabled))
                -1.0)))

    (define (side (game Game)) (→ Corner)
      (if (● game left-handed) (TopLeft) (TopRight)))

    (define (far-side (game Game)) (→ Corner)
      (if (● game left-handed) (TopRight) (TopLeft)))

    (define (seconds (ticks I64)) (→ String)
      (string-append (show (quotient (+ ticks 9) 10)) "s"))

    (define (clock-text (ticks I64)) (→ String)
      (let ((total (quotient ticks 10)))
        (string-append (show (quotient total 60))
                       ":"
                       (if (< (remainder total 60) 10) "0" "")
                       (show (remainder total 60)))))

    ;; ---- Dock ----

    ;; Hub health, energy, and the strength of the nests with the time to
    ;; the next attack.
    (define (readouts (game Game)) (→ Panel)
      (let* ((world (● game world)) (hub (● world hub))
             (tier (difficulty-tier (threat-tick world)))
             (until (- (next-attack-tick (● world tick)) (● world tick))))
        (Panel "readouts" (At (side game) 0)
               (list (Dial (Look "health"
                                 "health"
                                 "Hub health"
                                 (if (< (* 10 (● hub health)) (* 3 (hub-health))) (Danger) (Good))
                                 "")
                           (show (● hub health))
                           (/ (i64->f32 (● hub health)) (i64->f32 (hub-health))))
                     (Dial (face "energy" "energy" "Energy stored in the network")
                           (show (● world energy))
                           (min 1.0 (/ (i64->f32 (● world energy)) 400.0)))
                     (Dial (Look "threat"
                                 "threat"
                                 (string-append "Strength "
                                                (show tier)
                                                "; next attack in "
                                                (seconds until))
                                 (if (< until 100) (Warning) (Plain)) (seconds until))
                           (string-append "T" (show tier))
                           (/ (i64->f32 (remainder (threat-tick world) (difficulty-step)))
                              (i64->f32 (difficulty-step))))))))

    ;; The menu, or the results once the game is decided, then turning.
    (define (controls (game Game)) (→ Panel)
      (let ((decided (not (playing? (● game world)))))
        (Panel "controls" (At (side game) 1)
               (list (plain-button
                      (face "pause" (if decided "results" "pause") (if decided "Results" "Pause"))
                      "P"
                      (if decided (ShowResults) (OpenMenu)))
                     (plain-button (face "turn-left" "turn-left" "Turn left") "Q" (Turn -1))
                     (plain-button (face "turn-right" "turn-right" "Turn right") "E" (Turn 1))))))

    ;; ---- Construction ----

    ;; The build menu is the same for every selected cell: a pylon, a
    ;; turret, an extractor, an upgrade, a rush and closing, then below a
    ;; divider cancelling work and scavenging, or at the hub repair. Each is
    ;; greyed out where it does not apply.
    (define (construction (game Game)) (→ (List Panel))
      (match (● game selected)
        ((Some cell)
         (list (Panel "construction"
                      (At (side game) 0)
                      (append (build-menu game cell)
                              (Cons (label "divider" "") (care game cell))))))
        ((None) (Nil))))

    (define (build-menu (game Game) (cell Cell)) (→ (List Widget))
      (list (build-button game cell (Pylon))
            (build-button game cell (Turret))
            (build-button game cell (Extractor))
            (upgrade-button game cell)
            (rush-button game cell)
            (plain-button (face "close" "close" "Close") "5" (CloseCard))))

    (define (kind-icon (kind Kind)) (→ String)
      (match kind
        ((Extractor) "extractor")
        ((Pylon) "pylon")
        ((Turret) "turret")))

    (define (kind-key (kind Kind)) (→ String)
      (match kind
        ((Pylon) "1")
        ((Turret) "2")
        ((Extractor) "3")))

    (define (build-button (game Game) (cell Cell) (kind Kind)) (→ Widget)
      (let ((price (* (raise-cost kind 0) (if (● game rush) 5 1))))
        (command-button (Look (string-append "build-" (kind-icon kind)) (kind-icon kind)
                              (string-append (kind-name kind)
                                             ": "
                                             (show (quotient (raise-duration kind 0) 10))
                                             "s to build")
                              (if (opening-move? (● game world) kind) (Suggested) (Plain)) "")
                        (kind-key kind)
                        (show price)
                        (BuildAt kind cell)
                        (check (● game world) (Build kind cell (● game rush))))))

    ;; What the next level of the selected building, or the hub's next build
    ;; slot, costs.
    (define (upgrade-button (game Game) (cell Cell)) (→ Widget)
      (command-button (face "upgrade" "upgrade" "Upgrade")
                      "U"
                      (match (upgrade-cost (● game world) cell)
                        ((Some cost) (show cost))
                        ((None) ""))
                      (UpgradeAt cell) (check (● game world) (Upgrade cell))))

    (define (upgrade-cost (world World) (cell Cell)) (→ (Option I64))
      (cond ((hub-cell? (● world hub) cell)
             (let ((slots (● (● world hub) slots)))
               (if (< slots (maximum-slots)) (Some (slot-cost slots)) (None))))
            (else (match (building-at world cell)
                    ((Some b)
                     (if (and (built? b) (< (● b level) (maximum-level)))
                         (Some (raise-cost (● b kind) (● b level)))
                         (None)))
                    ((None) (None))))))

    ;; Work on the selected cell is rushed to its end; otherwise the button
    ;; makes new buildings rushed.
    (define (rush-button (game Game) (cell Cell)) (→ Widget)
      (match (cell-work (● game world) cell)
        ((Some work)
         (command-button (face "rush" "rush" "Rush: finish the work now")
                         "4"
                         (show (rush-price work))
                         (RushAt cell)
                         (check (● game world) (Rush cell))))
        ((None)
         (toggle-button
          (face "rush-orders" "rush" "Rush new buildings: ready at once for five times the price")
          "4"
          "×5"
          (ToggleRush)
          (● game rush)))))

    (define (cell-work (world World) (cell Cell)) (→ (Option Work))
      (if (hub-cell? (● world hub) cell)
          (● (● world hub) work)
          (match (building-at world cell)
            ((Some b) (● b work))
            ((None) (None)))))

    ;; Cancelling, greyed out while nothing is being built, then scavenging,
    ;; or at the hub repair.
    (define (care (game Game) (cell Cell)) (→ (List Widget))
      (list (cancel-button game cell)
            (if (hub-cell? (● (● game world) hub) cell)
                (repair-button game)
                (scavenge-button game cell))))

    (define (cancel-button (game Game) (cell Cell)) (→ Widget)
      (command-button (face "cancel" "cancel" "Cancel the work and refund it") "C"
                      (match (cell-work (● game world) cell)
                        ((Some w) (string-append "+" (show (work-refund w))))
                        ((None) ""))
                      (CancelAt cell) (check (● game world) (Cancel cell))))

    (define (scavenge-button (game Game) (cell Cell)) (→ Widget)
      (command-button (face "scavenge" "scavenge" "Scavenge: remove it for a fifth of its cost") "X"
                      (match (building-at (● game world) cell)
                        ((Some b) (string-append "+" (show (quotient (invested b) 5))))
                        ((None) ""))
                      (ScavengeAt cell) (check (● game world) (Scavenge cell))))

    (define (repair-button (game Game)) (→ Widget)
      (let ((world (● game world)))
        (command-button (face "repair" "repair" "Repair the hub to full health")
                        "F"
                        (show (repair-price (● world hub)))
                        (RepairHub)
                        (check world (Repair)))))

    ;; ---- Queue ----

    ;; The works in order: a ring for each holding a slot, and ! and dimmed
    ;; when unpowered. Tapping one goes to it.
    (define (queue (game Game)) (→ (List Panel))
      (let* ((world (● game world)) (all (tasks world)) (shown (take all 6)))
        (if (null? all)
            (Nil)
            (list (Panel "queue" (At (side game) 1)
                         (append
                          (map-indexed (lambda (index task) (queue-chip world index task)) shown)
                          (if (> (length all) 6)
                              (list
                               (label "queue-more" (string-append "+" (show (- (length all) 6)))))
                              (Nil))))))))

    (define (queue-chip (world World) (index I64) (task Task)) (→ Widget)
      (let* ((work (● task work))
             (cell (task-cell world task))
             (code (press-code (Locate cell))))
        (Button (Look (string-append "queue-" (show index))
                      (task-icon task)
                      (task-help task)
                      (if (● task supplied) (Plain) (Muted))
                      (if (● task supplied) "" "!"))
                "" "" (● code first) (● code second) (Enabled)
                (if (● task active)
                    (/ (i64->f32 (● work progress)) (i64->f32 (● work duration)))
                    -1.0))))

    (define (task-cell (world World) (task Task)) (→ Cell)
      (match (● task owner)
        ((OfHub) (● (● world hub) cell))
        ((OfBuilding b) (● b cell))))

    (define (task-icon (task Task)) (→ String)
      (match (● task owner)
        ((OfHub) "slots")
        ((OfBuilding b) (if (built? b) "upgrade" (kind-icon (● b kind))))))

    (define (task-help (task Task)) (→ String)
      (string-append (match (● task owner)
                       ((OfHub) "Build slot")
                       ((OfBuilding b)
                        (string-append (kind-name (● b kind))
                                       (if (built? b) " upgrade" ""))))
                     (cond ((not (● task supplied)) ", unpowered")
                           ((● task active) ", building")
                           (else ", waiting"))))

    ;; ---- Opening ----

    ;; Until the first extractor is built, the world waits under a title
    ;; banner that points to the glowing crystals, then, once one is
    ;; selected, to the build button the menu suggests. It links to the
    ;; guide.
    (define (opening (game Game)) (→ (List Panel))
      (if (opening? (● game world))
          (list (Panel "opening" (Banner)
                       (list (label "opening-title" "Siegework")
                             (opening-step game)
                             (Link (face "how-to-play"
                                         ""
                                         "The rules and controls, in the Snail-Scheme book")
                                   "How to play"
                                   (guide-url)))))
          (Nil)))

    ;; The step points to the glowing crystals, then to the build button;
    ;; each step's key lets the page color its strong words.
    (define (opening-step (game Game)) (→ Widget)
      (if (extractor-offered? game)
          (Text (look "opening-build")
                (list (Normal "Click the ") (Strong "build button") (Normal " to continue")))
          (Text (look "opening-crystal") (list (Normal "Click the ") (Strong "glowing crystal")))))

    (define (guide-url) (→ String) "https://tsnl.github.io/snail-scheme/games/siegework.html")

    ;; Whether the selected cell would take an extractor now.
    (define (extractor-offered? (game Game)) (→ Bool)
      (match (● game selected)
        ((Some cell)
         (match (check (● game world) (Build (Extractor) cell (● game rush)))
           ((Some _) #f)
           ((None) #t)))
        ((None) #f)))

    (define (opening-move? (world World) (kind Kind)) (→ Bool)
      (and (opening? world) (match kind ((Extractor) #t) (_ #f))))

    ;; ---- Objective ----

    ;; A star for each nest, filled once destroyed, and the time in play.
    (define (objective (game Game)) (→ Panel)
      (let ((world (● game world)))
        (Panel "objective" (At (far-side game) 0)
               (list (label "nests"
                            (list->string (map (lambda (nest) (if (= (● nest health) 0) #\★ #\☆))
                                               (● world nests))))
                     (label "elapsed" (clock-text (● world tick)))))))

    ;; ---- Notices ----

    ;; Under the nests, away from the dock so they never move the controls:
    ;; an alert while the colony was struck in the last eight seconds, which
    ;; goes to the latest attack, then, while a cell is selected, why the
    ;; last order on it was refused.
    (define (notices (game Game)) (→ (List Panel))
      (append (attack-alert game) (refusal game)))

    (define (attack-alert (game Game)) (→ (List Panel))
      (let ((world (● game world)))
        (match (find (lambda (a) (< (- (● world tick) (● a tick)) 80)) (● world alerts))
          ((Some alert) (list (Panel "alert" (At (far-side game) 0)
                                     (list (plain-button (Look "attack"
                                                               "danger"
                                                               "Under attack: go there"
                                                               (Danger)
                                                               "")
                                                         ""
                                                         (Locate (● alert cell)))))))
          ((None) (Nil)))))

    (define (refusal (game Game)) (→ (List Panel))
      (match (● game selected)
        ((Some _) (if (string=? (● game message) "")
                      (Nil)
                      (list (Panel "message"
                                   (At (far-side game) 0)
                                   (list (Label (Look "message" "" "" (Danger) "")
                                                (● game message)))))))
        ((None) (Nil))))

    ;; ---- Dialogs ----

    (define (dialogs (game Game)) (→ (List Panel))
      (match (● game menu)
        ((Closed) (Nil))
        ((Paused) (list (pause-dialog game)))
        ((Restarting) (list (confirm-dialog "restart" "Restart on a new map?" "Restart" (NewMap))))
        ((Resigning)
         (list (confirm-dialog "resign"
                               "Resign this colony? The map is revealed."
                               "Resign"
                               (ConfirmResign))))
        ((Results) (list (results-dialog game)))))

    (define (pause-dialog (game Game)) (→ Panel)
      (Panel "pause" (Dialog (● (press-code (Resume)) first))
             (list (label "pause-title" "Paused")
                   (plain-button (face "resume" "" "Resume") "Resume" (Resume))
                   (plain-button (face "restart" "" "Restart on a new map") "Restart…" (AskRestart))
                   (plain-button (face "resign" "" "Resign this colony") "Resign…" (AskResign))
                   (toggle-button (face "right-handed" "" "Controls on the right")
                                  "Right-handed"
                                  ""
                                  (Hand #f)
                                  (not (● game left-handed)))
                   (toggle-button (face "left-handed" "" "Controls on the left")
                                  "Left-handed"
                                  ""
                                  (Hand #t)
                                  (● game left-handed)))))

    (define (confirm-dialog (key String) (question String) (answer String) (command Command))
      (→ Panel)
      (Panel key (Dialog (● (press-code (OpenMenu)) first))
             (list (label (string-append key "-title") question)
                   (plain-button (Look (string-append "accept-" key) "" question (Danger) "")
                                 answer
                                 command)
                   (plain-button (face "back" "" "Back to the menu") "Back" (OpenMenu)))))

    ;; Time, combat, energy, buildings, nests and the seed, from the world.
    (define (results-dialog (game Game)) (→ Panel)
      (let* ((world (● game world)) (ledger (● world ledger)))
        (Panel "results" (Dialog (● (press-code (InspectMap)) first))
               (list (label "results-title"
                            (match (● world outcome)
                              ((Won) "Victory")
                              ((Lost) "Defeat")
                              ((Resigned) "Resigned")
                              ((Playing) "In play")))
                     (label "results-statistics"
                            (string-join
                             (list (string-append "Time " (clock-text (● world tick)))
                                   (string-append "Enemies destroyed " (show (● ledger kills)))
                                   (string-append "Energy produced "
                                                  (show (● ledger produced))
                                                  ", spent "
                                                  (show (● ledger spent)))
                                   (string-append "Buildings standing "
                                                  (show
                                                   (length (filter built? (● world buildings))))
                                                  ", lost "
                                                  (show (● ledger lost)))
                                   (string-append "Nests destroyed "
                                                  (show (- 3 (length (living-nests world))))
                                                  " of 3")
                                   (string-append "Map "
                                                  (show (● world seed))
                                                  ", "
                                                  (biome-name (● (● world land) biome))))
                             "\n"))
                     (plain-button (face "inspect" "" "Look over the map") "Map" (InspectMap))
                     (plain-button (face "new-map" "" "Start a new map") "New map" (NewMap))))))

    ;; ---- HUD ----

    (define (game-hud (game Game)) (→ (List Panel))
      (concatenate (list (list (readouts game))
                         (construction game)
                         (list (controls game))
                         (queue game)
                         (list (objective game))
                         (notices game)
                         (opening game)
                         (dialogs game))))

    ))
