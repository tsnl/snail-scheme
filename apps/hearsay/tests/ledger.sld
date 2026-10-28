;; A scripted favor-ledger game for seed 7: a job, a want bought with coins,
;; a rival's promise kept, a promise of yours refused and the prices that
;; follow, commands that cannot be done, and the final standings. The board
;; is printed from the queries the screen shows.
(import
 (snail-core base)
 (snail-core io)
 (hearsay ledger))

;; ---- Printing ----

(: show-lines (-> String (List String) Unit ! console))
(define (show-lines title lines)
  (write-line title)
  (for-each (lambda (line) (write-line (string-append "  " line)))
            (if (null? lines) (list "none") lines)))

(: choice-lines (-> (List Choice) (List String)))
(define (choice-lines choices)
  (map (lambda (choice)
         (string-append (Choice-text choice) ", " (Choice-caption choice)))
       choices))

;; Each fixer's standing and holdings; while the game is on, every choice
;; and the promises owed you, and once it is over, the result; then what
;; the last end of round did.
(: show-board (-> Ledger Unit ! console))
(define (show-board ledger)
  (write-line (ledger-header ledger))
  (for-each (lambda (who)
              (show-lines
               (string-append (fixer-name who) ": " (fixer-stats ledger who))
               (fixer-holdings ledger who)))
            (list you vee kit))
  (if (ledger-over? ledger)
      (write-line (ledger-result ledger))
      (begin (show-lines "Contacts" (choice-lines (contact-choices ledger)))
             (show-lines "Jobs" (choice-lines (job-choices ledger)))
             (show-lines "Vee offers" (choice-lines (offer-choices ledger vee)))
             (show-lines "Kit offers" (choice-lines (offer-choices ledger kit)))
             (show-lines "Promises"
                         (append (choice-lines (promise-choices ledger))
                                 (owed-lines ledger)))))
  (show-lines "Last round" (Ledger-last-round ledger))
  (write-line ""))

;; ---- Game ----

;; A step runs a command, or prints the board.
(enum Step
  (Run ((text String) (command Command)))
  (Board))

(: run-step (-> Ledger Step Ledger ! console))
(define (run-step ledger step)
  (match step
    ((Run text command)
     (write-line (string-append "> " text))
     (match (ledger-act ledger command)
       ((Ok result)
        (for-each write-line (Pair-second result))
        (Pair-first result))
       ((Err message) (write-line message) ledger)))
    ((Board) (show-board ledger) ledger)))

(define end (Run "end" (EndRound)))

(let ((ledger (new-ledger 7)))
  (show-board ledger)
  (show-board (fold-left run-step ledger
                         (list (Run "job 2" (Work 2))
                               (Run "meet ivo" (Meet 0))
                               (Run "accept 4" (Accept 4))
                               (Run "accept 7" (Accept 7))
                               end
                               (Run "honor 2" (Honor 2))
                               (Run "accept 99" (Accept 99))
                               end
                               end
                               (Board)
                               end
                               end
                               end
                               end
                               end
                               end
                               end))))
