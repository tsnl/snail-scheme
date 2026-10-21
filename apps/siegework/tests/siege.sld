;; The nests' schedule, then two colonies on seed 1: one leaves its hub
;; undefended, the other keeps adding turrets around it and widens its
;; build slots. Last, an enemy between two turrets holds to one of them.
(import
 (lofi base)
 (lofi io)
 (siegework grid)
 (only (siegework terrain) Land-starter)
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

(: started (-> World World))
(define (started world)
  (try world (Build (Extractor) (Land-starter (World-land world)) #f)))

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
(define lost (run (started (new-world 1)) 6000))
(report "undefended" lost)
(write-line (string-append "the lost colony's whole map is uncovered: "
                           (show (vector-fold (lambda (all seen) (and all seen)) #t (World-explored lost)))))
(define defended (defend (started (new-world 1)) 1000))
(report "defended" defended)
(report "defended" (defend defended 2000))

;; Turrets three cells west and east of the hub flank a sturdy enemy to
;; the north. Both hit it, but it turns only on the first and keeps after
;; that one.
(: flanked (-> World World))
(define (flanked world)
  (let ((world (run (try (try world (Build (Turret) (offset world -3 0) #f)) (Build (Turret) (offset world 3 0) #f)) 100)))
    (World-enemies-set world (list (Enemy 999 (Minion) 0 #f (offset world 0 4) (offset world 0 4) 2000 2000 (None) (None))))))

(: aggro-text (-> World String))
(define (aggro-text world)
  (match (find (lambda (e) (= (Enemy-id e) 999)) (World-enemies world))
    ((Some enemy) (match (Enemy-aggro enemy) ((Some id) (string-append "building " (show id))) ((None) "nothing")))
    ((None) "gone")))

(: watch (-> World I64 Unit ! console))
(define (watch world ticks)
  (if (> ticks 0)
      (let ((next (advance world)))
        (for-each (lambda (shot)
                    (write-line (string-append "tick " (show (World-tick next)) ": the turret at x " (show (Cell-x (Shot-from shot)))
                                               " fires; the enemy has turned on " (aggro-text next))))
                  (filter (lambda (shot) (= (Shot-tick shot) (World-tick next))) (World-shots next)))
        (watch next (- ticks 1)))
      (write-line (string-append "at tick " (show (World-tick world)) " the enemy has turned on " (aggro-text world)))))

(watch (flanked (started (new-world 1))) 40)
