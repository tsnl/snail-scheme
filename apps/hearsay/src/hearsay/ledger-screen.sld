;; The favor ledger in the browser: no scene, only panels. Every offer,
;; contact, job and promise you owe is a button with its terms beneath it,
;; enabled when it would succeed now and otherwise greyed out with the
;; reason in its help. A line under the standings says what needs doing
;; now, and a guide explains the game the first time.
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
   (hearsay cast)
   (hearsay hud))
  (begin

    ;; ---- State ----

    ;; `message` is what the last command did, a line each, or why it could
    ;; not be done. The choices are worked out after every command rather
    ;; than every frame, because judging one means trying it. `guide` is the
    ;; guide's open page, if any.
    (struct LedgerScreen
      ((seed I64)
       (ledger Ledger)
       (message (List String))
       (vee-offers (List Choice))
       (kit-offers (List Choice))
       (contacts (List Choice))
       (jobs (List Choice))
       (promises (List Choice))
       (guide (Option I64)))
      (deriving Serialize Deserialize))

    (: new-ledger-screen (-> I64 LedgerScreen))
    (define (new-ledger-screen seed)
      (refresh (LedgerScreen seed (new-ledger seed) (Nil) (Nil) (Nil) (Nil) (Nil) (Nil) (None))))

    (: refresh (-> LedgerScreen LedgerScreen))
    (define (refresh screen)
      (let* ((ledger (LedgerScreen-ledger screen))
             (screen (LedgerScreen-vee-offers-set screen (offer-choices ledger vee)))
             (screen (LedgerScreen-kit-offers-set screen (offer-choices ledger kit)))
             (screen (LedgerScreen-contacts-set screen (contact-choices ledger)))
             (screen (LedgerScreen-jobs-set screen (job-choices ledger))))
        (LedgerScreen-promises-set screen (promise-choices ledger))))

    ;; ---- Actions ----

    ;; Choice i of a group is the group's action with argument i. Action 5
    ;; ends the round and 6 deals a new game.
    (define action-vee-offers 1)
    (define action-contacts 2)
    (define action-jobs 3)
    (define action-promises 4)
    (define action-end 5)
    (define action-new 6)
    (define action-kit-offers 7)

    (: group-choices (-> LedgerScreen I32 (List Choice)))
    (define (group-choices screen group)
      (cond ((= group action-vee-offers) (LedgerScreen-vee-offers screen))
            ((= group action-contacts) (LedgerScreen-contacts screen))
            ((= group action-jobs) (LedgerScreen-jobs screen))
            ((= group action-promises) (LedgerScreen-promises screen))
            ((= group action-kit-offers) (LedgerScreen-kit-offers screen))
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
                                              ((EndRound) (Nil))
                                              (_ (Pair-second result))))))
        ((Err message) (LedgerScreen-message-set screen (list message)))))

    (: press (-> LedgerScreen I32 I32 LedgerScreen))
    (define (press screen action argument)
      (cond ((guide-action? action)
             (LedgerScreen-guide-set screen (turn-guide (LedgerScreen-guide screen) (length guide-pages) action)))
            ((= action action-end) (run screen (EndRound)))
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
             (rgb 16 20 28) 1.0 (Nil) (map (lambda (who) (walk-picture art (rival-picture who) (rival who))) (list vee kit))))

    ;; ---- Panels ----

    (: button (-> String String I32 Widget))
    (define (button key text action)
      (Button (look key) text "" action 0 (Enabled) -1.0))

    ;; Choice i of a group is a button pressing the group's action with
    ;; argument i.
    (: choice-buttons (-> (List Choice) I32 String (List Widget)))
    (define (choice-buttons choices group prefix)
      (map-indexed (lambda (index choice)
                     (choice-button (string-append prefix "-" (show index)) (Choice-text choice) (Choice-caption choice) group
                                    (i64->i32 index) (Choice-refusal choice) ""))
                   choices))

    ;; ---- Standings ----

    ;; Your coins, standing, record and markers. The dial fills as rounds
    ;; end.
    (: standings-panel (-> Ledger Panel))
    (define (standings-panel ledger)
      (Panel "standings" (At (TopLeft) 0)
             (list (label "title" "Favor ledger")
                   (Dial (look "round") (ledger-header ledger) (/ (i64->f32 (- (Ledger-round ledger) 1)) (i64->f32 round-count)))
                   (section-heading "you" "You") (label "you-stats" (fixer-stats ledger you))
                   (label "you-markers" (string-join (fixer-holdings ledger you) "\n")))))

    ;; A rival beside their portrait: their coins, standing, record, markers
    ;; and the job they are after, then their offers while the game is on.
    ;; Vee's column is left of Kit's.
    (: rival-panel (-> LedgerScreen I64 Panel))
    (define (rival-panel screen who)
      (let ((ledger (LedgerScreen-ledger screen)) (vee? (= who vee)))
        (Panel (if vee? "vee" "kit") (At (TopRight) (if vee? 1 0))
               (append (list (portrait "portrait" (rival-picture who) 2) (section-heading "name" (fixer-name who))
                             (label "stats" (fixer-stats ledger who)) (label "markers" (string-join (fixer-holdings ledger who) "\n")))
                       (if (ledger-over? ledger)
                           (Nil)
                           (section "offers" "Offers" "Nothing this round."
                                    (if vee?
                                        (choice-buttons (LedgerScreen-vee-offers screen) action-vee-offers "offer")
                                        (choice-buttons (LedgerScreen-kit-offers screen) action-kit-offers "offer"))))))))

    ;; What needs doing now: the result once the game is over, a promise
    ;; falling due, a job you can do, or else how to work toward one.
    (: hint (-> LedgerScreen Widget))
    (define (hint screen)
      (let ((ledger (LedgerScreen-ledger screen)))
        (cond ((ledger-over? ledger) (toned "hint" (Good) (string-append (ledger-result ledger) " Deal a new game, or go back to the menu.")))
              ((not (null? (due-now ledger)))
               (toned "hint" (Warning)
                      (string-append "You owe " (string-join (due-now ledger) " and ")
                                     " a marker by the end of this round. Honor it under Promises, or refusing costs 1 standing.")))
              ((any? (lambda (choice) (match (Choice-refusal choice) ((None) #t) (_ #f))) (LedgerScreen-jobs screen))
               (toned "hint" (Good) "You hold the markers for a job: do it under Jobs for standing."))
              (else (toned "hint" (Plain)
                           "Gather the markers a job needs: meet a contact's want, or trade with Vee and Kit. End the round when you are done.")))))

    ;; ---- Board ----

    ;; Your standing, what to do, the jobs and your promises down the left;
    ;; the contacts and the news beside them; each rival on the right.
    (: playing-panels (-> LedgerScreen (List Panel)))
    (define (playing-panels screen)
      (let ((ledger (LedgerScreen-ledger screen)))
        (list (standings-panel ledger)
              (Panel "hint" (At (TopLeft) 0) (list (hint screen)))
              (Panel "jobs" (At (TopLeft) 0)
                     (section "jobs" "Jobs: one marker per ability" "No jobs open." (choice-buttons (LedgerScreen-jobs screen) action-jobs "job")))
              (Panel "promises" (At (TopLeft) 0)
                     (section "promises" "Promises" "None yet."
                              (append (choice-buttons (LedgerScreen-promises screen) action-promises "promise") (line-labels "owed" (owed-lines ledger)))))
              (Panel "contacts" (At (TopLeft) 1)
                     (append (section "contacts" "Contacts: meet a want, get a marker" "No contacts."
                                      (choice-buttons (LedgerScreen-contacts screen) action-contacts "contact"))
                             (list (button "end" "End the round" action-end) (button "new" "New game" action-new))))
              (news-panel screen) (rival-panel screen vee) (rival-panel screen kit))))

    ;; What the last command said, and what the last end of round did.
    (: news-panel (-> LedgerScreen Panel))
    (define (news-panel screen)
      (Panel "news" (At (TopLeft) 1)
             (append (line-labels "message" (LedgerScreen-message screen))
                     (section "last-round" "Last end of round" "Nothing yet." (line-labels "last-round" (Ledger-last-round (LedgerScreen-ledger screen)))))))

    (: final-panels (-> LedgerScreen (List Panel)))
    (define (final-panels screen)
      (list (standings-panel (LedgerScreen-ledger screen)) (Panel "hint" (At (TopLeft) 0) (list (hint screen)))
            (Panel "contacts" (At (TopLeft) 1) (list (button "new" "New game" action-new))) (news-panel screen)
            (rival-panel screen vee) (rival-panel screen kit)))

    ;; ---- Guide ----

    (: guide-pages (List Page))
    (define guide-pages
      (list (Page "What this experiment tests"
                  (list "The favor ledger asks one question: does an economy of favors produce interesting trades, or collapse into hoarding?"
                        "While you play, notice: do you broker, buying a marker from one rival to sell to the other? Do you accept promises, and does refusing one change what Vee and Kit offer you? Does lapsing keep markers moving, or does hoarding still win?")
                  (Nil))
            (Page "Markers"
                  (list "A marker is a favor a contact owes you. It lends you that contact's ability once: doors, muscle, medicine, fencing, paperwork or eyes."
                        "A marker can be spent, given or traded, but never copied, and it lapses at the end of the second round after it was granted. Yours are listed under You at the top left.")
                  (Nil))
            (Page "Jobs"
                  (list "The most standing after eight rounds wins, and coins break ties. Jobs pay standing: a job takes one marker for each ability it lists."
                        "A job needing two abilities pays 4 coins and 1 standing; one needing three pays 6 coins and 2. Vee and Kit chase jobs too, and each shows the job it is after.")
                  (list (portrait "guide-vee" (rival-picture vee) 2) (portrait "guide-kit" (rival-picture kit) 2)))
            (Page "Getting markers"
                  (list "Each contact wants one thing: coins, or a marker with another ability. Meet the want and they grant you one of their markers, once a round."
                        "Vee and Kit, on the right, offer to buy and sell markers, and to trade promises for coins. Each offer can be taken once a round."
                        "A greyed-out button says why when you point at it.")
                  (Nil))
            (Page "Promises and the end of a round"
                  (list "A promise is a debt of one marker with an ability, due at the end of a round. Honor yours under Promises in time: one still owed when it falls due is refused, and refusing costs 1 standing."
                        "Once you refuse, Vee and Kit pay less, charge more, and stop asking for your promises. Vee keeps every promise she can; Kit keeps one only if he can spare the marker."
                        "When you are done, end the round: rivals do their jobs and gain a marker, markers lapse, and promises fall due.")
                  (Nil))))

    ;; `first` are panels to show before the screen's own.
    (: ledger-screen-hud (-> LedgerScreen (List Panel) (List Panel)))
    (define (ledger-screen-hud screen first)
      (concatenate
       (list first (if (ledger-over? (LedgerScreen-ledger screen)) (final-panels screen) (playing-panels screen))
             (match (LedgerScreen-guide screen)
               ((Some page) (list (guide-panel "Favor ledger" guide-pages page)))
               ((None) (Nil))))))

    ))
