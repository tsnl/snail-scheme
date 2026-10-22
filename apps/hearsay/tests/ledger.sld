;; A scripted favor-ledger game for seed 7: a job, a want bought with coins,
;; a rival's promise kept, a promise of yours refused and the prices that
;; follow, commands that cannot be done, and the final standings.
(import
 (lofi base)
 (lofi io)
 (hearsay ledger))

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
       ((Ok result) (write-line (Pair-second result)) (Pair-first result))
       ((Err message) (write-line message) ledger)))
    ((Board) (write-line (ledger-board ledger)) ledger)))

(define end (Run "end" (EndRound)))

(let ((ledger (new-ledger 7)))
  (write-line (ledger-intro))
  (write-line (ledger-board ledger))
  (write-line (ledger-board (fold-left run-step ledger
                                       (list (Run "job 2" (Work 2)) (Run "meet ivo" (Meet 0)) (Run "accept 4" (Accept 4))
                                             (Run "accept 7" (Accept 7)) end
                                             (Run "honor 2" (Honor 2)) (Run "accept 99" (Accept 99)) end
                                             end (Board)
                                             end end end end end end end)))))
