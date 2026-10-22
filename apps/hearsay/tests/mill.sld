;; Scripted rumor-mill games: a won Two faces, a smear lost by lying low, a
;; smear won by getting ahead of the story, a lie that is exposed, and a
;; witness who is paid to forget and then hears the story back. Each game
;; ends with what the screen would show, printed from the same queries.
(import
 (lofi base)
 (lofi io)
 (hearsay mill))

;; ---- Printing ----

;; "reliable 3, dangerous 1", or "-".
(: beliefs-text (-> (List (Pair Trait I64)) String))
(define (beliefs-text beliefs)
  (if (null? beliefs)
      "-"
      (string-join (map (lambda (belief) (string-append (trait-name (Pair-first belief)) " " (show (Pair-second belief)))) beliefs)
                   ", ")))

;; Who a person is, what they believe and the stories they hold, as the
;; person panel shows them.
(: show-person (-> Mill I64 Unit ! console))
(define (show-person mill person)
  (write-line (string-append (show person) " " (person-name person) ", " (audience-name (audience-of person))
                             (if (hub? person) ", hub" "") ". Ties: " (string-join (map first-name (neighbors person)) ", ") "."))
  (write-line (string-append "Believes: " (beliefs-text (person-beliefs mill person)) "."))
  (match (story-lines mill person)
    ((Nil) (write-line "Holds no stories about you."))
    (stories (for-each (lambda (story) (write-line (string-append "  " story))) stories))))

(: progress-text (-> Progress String))
(define (progress-text progress)
  (match progress
    ((Met) "met")
    ((Unmet) "unmet")
    ((Upcoming) "upcoming")
    ((Due) "due now")
    ((Done) "done")))

;; The shift and coins, what each audience and its people believe, the
;; liabilities and the goal, then the forecast or the verdict.
(: show-board (-> Mill Unit ! console))
(define (show-board mill)
  (write-line (string-append (Rules-name (scenario-rules (Mill-scenario mill))) ": "
                             (if (mill-over? mill)
                                 (string-append "after shift " (show (last-shift mill)))
                                 (string-append "shift " (show (Mill-shift mill)) " of " (show (last-shift mill))))
                             ", " (show (Mill-coins mill)) " coins."))
  (for-each (lambda (audience)
              (write-line (string-append (audience-name audience) ": " (beliefs-text (audience-beliefs mill audience))))
              (for-each (lambda (person)
                          (write-line (string-append "  " (person-name person) (if (hub? person) " (hub)" "") ": "
                                                     (beliefs-text (person-beliefs mill person)) (if (quiet? mill person) " [quiet]" ""))))
                        (filter (lambda (person) (= (audience-of person) audience)) (iota person-count))))
            audiences)
  (for-each (lambda (text) (write-line (string-append "Liability: " text))) (liabilities mill))
  (for-each (lambda (goal) (write-line (string-append "Goal: " (Goal-text goal) " (" (progress-text (Goal-progress goal)) ")")))
            (mill-goals mill))
  (match (mill-result mill)
    ((Some (Pair won? text)) (write-line text))
    ((None)
     (when (forced? mill) (write-line "This shift is forced."))
     (for-each (lambda (line) (write-line (string-append "If you lie low: " line))) (forecast mill)))))

;; ---- Games ----

;; A step takes a shift or looks at a person, and is printed as `text`.
(enum Step
  (Act ((text String) (action Action)))
  (Look ((text String) (person I64))))

(: run-step (-> Mill Step Mill ! console))
(define (run-step mill step)
  (match step
    ((Act text action)
     (write-line (string-append "> " text))
     (match (take-shift mill action)
       ((Ok result) (for-each write-line (Pair-second result)) (Pair-first result))
       ((Err message) (write-line message) mill)))
    ((Look text person)
     (write-line (string-append "> " text))
     (show-person mill person)
     mill)))

(: game (-> Scenario (List Step) Unit ! console))
(define (game scenario steps)
  (write-line (string-append "==== " (Rules-name (scenario-rules scenario))))
  (show-board (fold-left run-step (new-mill scenario) steps))
  (write-line ""))

(define wait (Act "wait" (Wait)))

;; People by number: Ana 0, Gus 6, Hana 7, Mo 12, Nia 13, Oda 14, Pim 15,
;; Rhea 17, Tam 19.
(game (TwoFaces) (list (Act "deliver mo" (Do (Deliver) 12)) wait wait (Act "threat pim" (Do (Threat) 15)) wait
                       (Act "pay nia" (Pay 13)) (Look "look ana" 0) wait wait wait wait (Look "look gus" 6)))
(game (Smear) (list wait wait))
(game (Smear) (list (Act "pay oda" (Pay 14)) (Act "deliver hana" (Do (Deliver) 7)) (Act "pay nia" (Pay 13)) (Look "look tam" 19)
                    wait wait wait wait wait wait wait))
(game (Sandbox) (list (Act "lie harmless rhea" (Mislead (Harmless) 17)) (Act "rough nia" (Do (Rough) 13)) (Look "look rhea" 17) wait))
(game (Sandbox) (list (Act "rough ana" (Do (Rough) 0)) wait (Act "pay ana" (Pay 0)) (Look "look ana" 0)))
