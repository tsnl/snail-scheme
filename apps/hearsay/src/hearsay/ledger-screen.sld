;; The favor ledger in the browser: no scene, only panels. Every offer,
;; contact, job and promise you owe is a button, enabled when it would
;; succeed now and otherwise greyed out with the reason in its help.
(define-library (hearsay ledger-screen)
  (export
   LedgerScreen
   new-ledger-screen
   update-ledger-screen
   view-ledger-screen
   ledger-screen-hud)
  (import
   (lofi base)
   (lofi wire)
   (lofi app)
   (lpc wardrobe)
   (hearsay ledger)
   (hearsay cast))
  (begin

    ;; ---- State ----

    ;; The choices are worked out after every command rather than every
    ;; frame, because judging one means trying it.
    (struct LedgerScreen
      ((seed I64)
       (ledger Ledger)
       (message String)
       (offers (List Choice))
       (contacts (List Choice))
       (jobs (List Choice))
       (promises (List Choice)))
      (deriving Serialize Deserialize))

    (: new-ledger-screen (-> I64 LedgerScreen))
    (define (new-ledger-screen seed)
      (refresh (LedgerScreen seed (new-ledger seed) (ledger-intro) (Nil) (Nil) (Nil) (Nil))))

    (: refresh (-> LedgerScreen LedgerScreen))
    (define (refresh screen)
      (let* ((ledger (LedgerScreen-ledger screen))
             (screen (LedgerScreen-offers-set screen (offer-choices ledger)))
             (screen (LedgerScreen-contacts-set screen (contact-choices ledger)))
             (screen (LedgerScreen-jobs-set screen (job-choices ledger))))
        (LedgerScreen-promises-set screen (promise-choices ledger))))

    ;; ---- Actions ----

    ;; Choice i of group g (offers 1, contacts 2, jobs 3, promises 4) is
    ;; action g with argument i. Action 5 ends the round and 6 deals a new
    ;; game.
    (define action-end 5)
    (define action-new 6)

    (: group-choices (-> LedgerScreen I32 (List Choice)))
    (define (group-choices screen group)
      (case group
        ((1) (LedgerScreen-offers screen))
        ((2) (LedgerScreen-contacts screen))
        ((3) (LedgerScreen-jobs screen))
        ((4) (LedgerScreen-promises screen))
        (else (Nil))))

    (: command-at (-> LedgerScreen I32 I32 (Option Command)))
    (define (command-at screen group index)
      (let ((choices (group-choices screen group)))
        (if (and (>= index 0) (< (i32->i64 index) (length choices)))
            (Some (Choice-command (list-ref choices (i32->i64 index))))
            (None))))

    ;; The end of a round needs no message: the board shows what it did.
    (: run (-> LedgerScreen Command LedgerScreen))
    (define (run screen command)
      (match (ledger-act (LedgerScreen-ledger screen) command)
        ((Ok result)
         (refresh (LedgerScreen-message-set (LedgerScreen-ledger-set screen (Pair-first result))
                                            (match command
                                              ((EndRound) "")
                                              (_ (Pair-second result))))))
        ((Err message) (LedgerScreen-message-set screen message))))

    (: press (-> LedgerScreen I32 I32 LedgerScreen))
    (define (press screen action argument)
      (cond ((= action action-end) (run screen (EndRound)))
            ((= action action-new) (new-ledger-screen (+ (LedgerScreen-seed screen) 1)))
            (else (match (command-at screen action argument)
                    ((Some command) (run screen command))
                    ((None) screen)))))

    (: update-ledger-screen (-> LedgerScreen Input LedgerScreen))
    (define (update-ledger-screen screen input)
      (match input
        ((Press action argument) (press screen action argument))
        (_ screen)))

    ;; The scene is empty; its pictures are the rivals' portraits for the
    ;; HUD, from the sheets `art` gives.
    (: view-ledger-screen (-> LedgerScreen (-> String (Option Source)) Frame))
    (define (view-ledger-screen screen art)
      (Frame (Camera (Vec3 0.0 10.0 10.0) (Vec3 0.0 0.0 0.0) (Perspective 0.8)) (Light (Vec3 0.0 1.0 0.0) 0.0 1.0)
             (rgb 16 20 28) 1.0 (Nil) (map (lambda (index) (walk-picture art (rival-key index) (rival index))) (list 0 1))))

    ;; Vee's picture is 200 and Kit's 201.
    (: rival-key (-> I64 I32))
    (define (rival-key index)
      (i64->i32 (+ 200 index)))

    ;; ---- Panels ----

    (: label (-> String String Widget))
    (define (label key text)
      (Label (look key) text))

    (: button (-> String String I32 Widget))
    (define (button key text action)
      (Button (look key) text "" action 0 (Enabled) -1.0))

    ;; A choice is enabled when it would succeed, and otherwise disabled
    ;; with the reason as its help.
    (: choice-buttons (-> (List Choice) I32 String (List Widget)))
    (define (choice-buttons choices group prefix)
      (map-indexed (lambda (index choice)
                     (let ((key (string-append prefix "-" (show index))))
                       (match (Choice-refusal choice)
                         ((None) (Button (look key) (Choice-text choice) "" group (i64->i32 index) (Enabled) -1.0))
                         ((Some why) (Button (Look-help-set (look key) why) (Choice-text choice) "" group (i64->i32 index) (Disabled) -1.0)))))
                   choices))

    ;; A title over its widgets, or over "none".
    (: titled (-> String (List Widget) (List Widget)))
    (define (titled title widgets)
      (Cons (label (string-append "title-" title) title) (if (null? widgets) (list (label (string-append "none-" title) "none")) widgets)))

    (: lines (-> (List String) String))
    (define (lines texts)
      (string-join texts "\n"))

    (: promise-widgets (-> LedgerScreen (List Widget)))
    (define (promise-widgets screen)
      (titled "Promises"
              (append (choice-buttons (LedgerScreen-promises screen) 4 "promise")
                      (map-indexed (lambda (index line) (label (string-append "owed-" (show index)) line))
                                   (owed-lines (LedgerScreen-ledger screen))))))

    (: last-round-label (-> Ledger Widget))
    (define (last-round-label ledger)
      (label "last-round" (lines (Cons "Last round:" (last-round-lines ledger)))))

    (: playing-panels (-> LedgerScreen (List Panel)))
    (define (playing-panels screen)
      (let ((ledger (LedgerScreen-ledger screen)))
        (list (Panel "fixers" (At (TopLeft) 0)
                     (list (label "round" (ledger-header ledger)) (label "fixers" (lines (fixer-lines ledger)))))
              (Panel "rivals" (At (TopLeft) 1) (rival-widgets))
              (Panel "jobs" (At (TopLeft) 1) (titled "Jobs" (choice-buttons (LedgerScreen-jobs screen) 3 "job")))
              (Panel "offers" (At (TopRight) 0)
                     (append (titled "Offers" (choice-buttons (LedgerScreen-offers screen) 1 "offer")) (promise-widgets screen)))
              (Panel "contacts" (At (BottomLeft) 0)
                     (append (choice-buttons (LedgerScreen-contacts screen) 2 "contact")
                             (list (button "end" "End the round" action-end) (button "new" "New game" action-new))))
              (Panel "news" (At (BottomRight) 0)
                     (append (if (string=? (LedgerScreen-message screen) "") (Nil) (list (label "message" (LedgerScreen-message screen))))
                             (list (last-round-label ledger)))))))

    ;; The rivals' portraits, each beside their name.
    (: rival-widgets (-> (List Widget)))
    (define (rival-widgets)
      (list (portrait "vee" (rival-key 0) 2) (label "vee-name" "Vee") (portrait "kit" (rival-key 1) 2) (label "kit-name" "Kit")))

    (: final-panels (-> LedgerScreen (List Panel)))
    (define (final-panels screen)
      (let ((ledger (LedgerScreen-ledger screen)))
        (list (Panel "standings" (At (TopLeft) 0)
                     (list (label "round" (ledger-header ledger)) (label "fixers" (lines (fixer-lines ledger)))
                           (label "result" (ledger-result ledger)) (last-round-label ledger)))
              (Panel "rivals" (At (TopLeft) 1) (rival-widgets))
              (Panel "contacts" (At (BottomLeft) 0) (list (button "new" "New game" action-new))))))

    ;; `first` are panels to show before the screen's own.
    (: ledger-screen-hud (-> LedgerScreen (List Panel) (List Panel)))
    (define (ledger-screen-hud screen first)
      (append first (if (ledger-over? (LedgerScreen-ledger screen)) (final-panels screen) (playing-panels screen))))

    ))
