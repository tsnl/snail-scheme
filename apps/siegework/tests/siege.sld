;; The nests' schedule, then two colonies on seed 1: one leaves its hub
;; undefended, the other keeps adding turrets around it and widens its
;; build slots.
(import
 (lofi base)
 (lofi io)
 (siegework grid)
 (siegework world)
 (siegework colony)
 (siegework siege)
 (siegework simulation))

(: run (-> World I64 World))
(define (run world ticks)
  (if (or (= ticks 0) (not (playing? world))) world (run (advance world) (- ticks 1))))

(: try (-> World Action World))
(define (try world action)
  (match (act world action)
    ((Ok world) world)
    ((Err _) world)))

(: outcome-text (-> Outcome String))
(define (outcome-text outcome)
  (match outcome
    ((Playing) "playing")
    ((Won) "won")
    ((Lost) "lost")
    ((Resigned) "resigned")))

(: report (-> String World Unit ! console))
(define (report name world)
  (write-line (string-append name ": tick " (show (World-tick world)) ", buildings " (show (length (World-buildings world)))
                             ", hub " (show (Hub-health (World-hub world))) ", enemies " (show (length (World-enemies world)))
                             ", kills " (show (Ledger-kills (World-ledger world))) ", lost " (show (Ledger-lost (World-ledger world)))
                             ", opened rock " (show (vector-fold (lambda (n open) (if open (+ n 1) n)) 0 (World-opened world)))
                             ", " (outcome-text (World-outcome world)))))

(: attack-text (-> I64 String))
(define (attack-text tick)
  (string-append (show tick) " " (match (attack-kind tick) ((Regular) "wave") ((Raid) "raid") ((Heavy) "boss")) " of " (show (attack-size tick))))

(: offset (-> World I64 I64 Cell))
(define (offset world dx dy)
  (let ((hub (Hub-cell (World-hub world))))
    (Cell (+ (Cell-x hub) dx) (+ (Cell-y hub) dy))))

;; The starter crystal sits four cells east and two north of the hub.
(: started (-> World World))
(define (started world)
  (try world (Build (Extractor) (offset world 4 -2) #f)))

(: reinforce (-> World World))
(define (reinforce world)
  (try (fold-left (lambda (world d) (try world (Build (Turret) (offset world (Pair-first d) (Pair-second d)) #f)))
                  world (list (Pair -2 0) (Pair 0 2) (Pair 2 0) (Pair 0 -2) (Pair -2 2) (Pair 2 -2) (Pair 2 2) (Pair -2 -2)))
       (Upgrade (offset world 0 0))))

(: defend (-> World I64 World))
(define (defend world ticks)
  (if (or (<= ticks 0) (not (playing? world))) world (defend (run (reinforce world) 100) (- ticks 100))))

(write-line (string-append "attacks: " (string-join (map attack-text (let loop ((tick 0) (found (Nil)))
                                                                       (if (= (length found) 12) (reverse found) (let ((next (next-attack-tick tick))) (loop next (Cons next found))))))
                                                    ", ")))
(write-line (string-append "next attack after tick 5000: " (attack-text (next-attack-tick 5000))))
(report "undefended" (run (started (new-world 1)) 6000))
(define defended (defend (started (new-world 1)) 1000))
(report "defended" defended)
(report "defended" (defend defended 2000))
