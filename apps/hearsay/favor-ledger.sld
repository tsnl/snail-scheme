;; Plays the favor ledger at a terminal:
;;   ./lofi run -I apps/hearsay/src apps/hearsay/favor-ledger.sld [SEED]
;; The same SEED deals the same game.
(import
 (lofi base)
 (lofi io)
 (hearsay ledger))

(: play (-> Ledger Unit ! console))
(define (play ledger)
  (write-line "")
  (write-line (ledger-board ledger))
  (unless (ledger-over? ledger)
    (write-string "> ")
    (match (read-line)
      ((Some line)
       (unless (string=? line "quit")
         (let ((result (ledger-command ledger line)))
           (write-line (Pair-second result))
           (play (Pair-first result)))))
      ((None) (unit)))))

(let ((ledger (new-ledger (match (command-line)
                            ((Cons program (Cons argument _)) (match (string->i64 argument) ((Some seed) seed) ((None) 1)))
                            (_ 1)))))
  (write-line (ledger-intro ledger))
  (play ledger))
