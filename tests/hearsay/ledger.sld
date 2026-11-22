;; A scripted favor-ledger game for seed 7: a job, a want bought with coins,
;; a rival's promise kept, a promise of yours refused and the prices that
;; follow, commands that cannot be done, and the final standings. The board
;; is printed from the queries the screen shows.
(import
 (snail core base)
 (snail core io)
 (apps hearsay ledger))

;; ---- Printing ----

(define (show-lines (out OutputPort) (title String) (lines (List String))) (→ Unit) (! mut)
  (write-line out title)
  (for-each (lambda (line) (write-line out (string-append "  " line)))
            (if (null? lines) (list "none") lines)))

(define (choice-lines (choices (List Choice))) (→ (List String))
  (map (lambda (choice) (string-append (● choice text) ", " (● choice caption))) choices))

;; Each fixer's standing and holdings; while the game is on, every choice
;; and the promises owed you, and once it is over, the result; then what
;; the last end of round did.
(define (show-board (out OutputPort) (ledger Ledger)) (→ Unit) (! mut)
  (write-line out (ledger-header ledger))
  (for-each (lambda (who)
              (show-lines out (string-append (fixer-name who) ": " (fixer-stats ledger who))
                          (fixer-holdings ledger who)))
            (list you vee kit))
  (if (ledger-over? ledger)
      (write-line out (ledger-result ledger))
      (begin (show-lines out "Contacts" (choice-lines (contact-choices ledger)))
             (show-lines out "Jobs" (choice-lines (job-choices ledger)))
             (show-lines out "Vee offers" (choice-lines (offer-choices ledger vee)))
             (show-lines out "Kit offers" (choice-lines (offer-choices ledger kit)))
             (show-lines out "Promises"
                         (append (choice-lines (promise-choices ledger)) (owed-lines ledger)))))
  (show-lines out "Last round" (● ledger last-round))
  (write-line out ""))

;; ---- Game ----

;; A step runs a command, or prints the board.
(enum Step
  (Run ((text String) (command Command)))
  (Board))

(define (run-step (out OutputPort) (ledger Ledger) (step Step)) (→ Ledger) (! mut)
  (match step
    ((Run text command)
     (write-line out (string-append "> " text))
     (match (ledger-act ledger command)
       ((Ok result) (for-each (lambda (text) (write-line out text)) (● result second)) (● result first))
       ((Err message) (write-line out message) ledger)))
    ((Board) (show-board out ledger) ledger)))

(define (end) (→ Step) (Run "end" (EndRound)))

(define (main (out OutputPort)) (→ Unit) (! mut)

  (let ((ledger (new-ledger 7)))
    (show-board out ledger)
    (show-board out (fold-left (lambda (mill step) (run-step out mill step)) ledger
                           (list (Run "job 2" (Work 2))
                                 (Run "meet ivo" (Meet 0))
                                 (Run "accept 4" (Accept 4))
                                 (Run "accept 7" (Accept 7))
                                 (end)
                                 (Run "honor 2" (Honor 2))
                                 (Run "accept 99" (Accept 99))
                                 (end)
                                 (end)
                                 (Board)
                                 (end)
                                 (end)
                                 (end)
                                 (end)
                                 (end)
                                 (end)
                                 (end)))))
  (unit))
