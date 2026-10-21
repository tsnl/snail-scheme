;; Waves against two colonies on seed 11, both started with an extractor:
;; one leaves its hub undefended, the other adds two turrets beside it.
(import
 (lofi base)
 (lofi io)
 (siegework grid)
 (siegework world)
 (siegework colony)
 (siegework simulation))

(: run (-> World I64 World))
(define (run world ticks)
  (if (or (= ticks 0) (not (playing? world))) world (run (advance world) (- ticks 1))))

(: order (-> World Action World))
(define (order world action)
  (match (act world action)
    ((Ok world) world)
    ((Err rejection) (panic (rejection-text rejection)))))

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
                             ", hub " (show (Hub-health (World-hub world))) ", kills " (show (Ledger-kills (World-ledger world)))
                             ", " (outcome-text (World-outcome world)))))

;; The starter crystal sits four cells east and two north of the hub.
(: started (-> World World))
(define (started world)
  (let ((hub (Hub-cell (World-hub world))))
    (order world (Build (Extractor) (Cell (+ (Cell-x hub) 4) (- (Cell-y hub) 2)) #f))))

(: defended (-> World World))
(define (defended world)
  (let ((hub (Hub-cell (World-hub world))))
    (order (order world (Build (Turret) (Cell (- (Cell-x hub) 2) (Cell-y hub)) #f)) (Build (Turret) (Cell (Cell-x hub) (+ (Cell-y hub) 2)) #f))))

(report "undefended" (run (started (new-world 11)) 6000))
(report "defended" (run (defended (started (new-world 11))) 2000))
