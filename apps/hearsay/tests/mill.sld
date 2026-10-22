;; Scripted rumor-mill games: a won Two faces, a smear lost by lying low, a
;; smear won by getting ahead of the story, a lie that is exposed, and a
;; witness who is paid to forget and then hears the story back.
(import
 (lofi base)
 (lofi io)
 (hearsay mill))

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
       ((Ok result) (write-line (Pair-second result)) (Pair-first result))
       ((Err message) (write-line message) mill)))
    ((Look text person)
     (write-line (string-append "> " text))
     (write-line (look-text mill person))
     mill)))

(: game (-> I64 (List Step) Unit ! console))
(define (game scenario steps)
  (write-line (string-append "==== " (mill-scenario-name scenario)))
  (write-line (mill-board (fold-left run-step (new-mill scenario) steps)))
  (write-line ""))

(define wait (Act "wait" (Wait)))

;; People by number: Ana 0, Gus 6, Hana 7, Mo 12, Nia 13, Oda 14, Pim 15,
;; Rhea 17, Tam 19.
(game 0 (list (Act "deliver mo" (Do (Deliver) 12)) wait wait (Act "threat pim" (Do (Threat) 15)) wait
              (Act "pay nia" (Pay 13)) (Look "look ana" 0) wait wait wait wait (Look "look gus" 6)))
(game 1 (list wait wait))
(game 1 (list (Act "pay oda" (Pay 14)) (Act "deliver hana" (Do (Deliver) 7)) (Act "pay nia" (Pay 13)) (Look "look tam" 19)
              wait wait wait wait wait wait wait))
(game 2 (list (Act "lie harmless rhea" (Mislead (Harmless) 17)) (Act "rough nia" (Do (Rough) 13)) (Look "look rhea" 17) wait))
(game 2 (list (Act "rough ana" (Do (Rough) 0)) wait (Act "pay ana" (Pay 0)) (Look "look ana" 0)))
