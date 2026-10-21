;; A scripted favor-ledger game for seed 7: a job, a want bought with coins,
;; a rival's promise kept, a promise of yours refused and the prices that
;; follow, invalid commands, and the final standings.
(import
 (lofi base)
 (lofi io)
 (hearsay ledger))

;; `board` prints the board instead of running a command.
(: play (-> Ledger (List String) Ledger ! console))
(define (play ledger commands)
  (match commands
    ((Nil) ledger)
    ((Cons "board" rest) (write-line (ledger-board ledger)) (play ledger rest))
    ((Cons command rest)
     (write-line (string-append "> " command))
     (let ((result (ledger-command ledger command)))
       (write-line (Pair-second result))
       (play (Pair-first result) rest)))))

(let ((ledger (new-ledger 7)))
  (write-line (ledger-intro ledger))
  (write-line (ledger-board ledger))
  (write-line (ledger-board (play ledger
                                  (list "job 2" "meet ivo" "accept 4" "accept 7" "end"
                                        "honor 2" "accept 99" "dance" "end"
                                        "end" "board"
                                        "end" "end" "end" "end" "end" "end")))))
