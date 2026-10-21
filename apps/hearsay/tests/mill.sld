;; Scripted rumor-mill games: a won Two faces, a smear lost by lying low, a
;; smear won by getting ahead of the story, a lie that is exposed, and a
;; witness who is paid to forget and then hears the story back.
(import
 (lofi base)
 (lofi io)
 (hearsay mill))

(: play (-> Mill (List String) Mill ! console))
(define (play mill commands)
  (match commands
    ((Nil) mill)
    ((Cons command rest)
     (write-line (string-append "> " command))
     (let ((result (mill-command mill command)))
       (write-line (Pair-second result))
       (play (Pair-first result) rest)))))

(: game (-> I64 (List String) Unit ! console))
(define (game scenario commands)
  (let ((mill (new-mill scenario)))
    (write-line (string-append "==== " (mill-scenario-name scenario)))
    (write-line (mill-board (play mill commands)))
    (write-line "")))

(game 0 (list "deliver mo" "wait" "wait" "threat pim" "wait" "pay nia" "look ana" "wait" "wait" "wait" "wait" "look gus"))
(game 1 (list "wait" "wait"))
(game 1 (list "pay oda" "deliver hana" "pay nia" "look tam" "wait" "wait" "wait" "wait" "wait" "wait" "wait"))
(game 2 (list "lie harmless rhea" "rough nia" "look rhea" "wait" "nobody here" "pay 99"))
(game 2 (list "rough ana" "wait" "pay ana" "look ana"))
