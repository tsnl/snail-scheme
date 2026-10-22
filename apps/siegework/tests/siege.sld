;; The nests' schedule, then two colonies on seed 1: one leaves its hub
;; undefended, the other keeps a ring of turrets around it. Then staged
;; enemies on seed 3, a meadow with open ground east of the hub:
;;
;; - an aggressive enemy attacks the nearest structure in sight, then the
;;   next, then makes for the hub;
;; - a calm one shot by a turret keeps on for the hub, with no revenge;
;; - with the hub walled in, an enemy has no walking route, so it digs
;;   through the wall;
;; - workers beside an enemy strike back.
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
                             ", hub " (show (Hub-health (World-hub world))) ", workers " (show (length (World-workers world)))
                             ", enemies " (show (length (World-enemies world)))
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

(: first-pylon (-> World (List (Pair I64 I64)) World))
(define (first-pylon world places)
  (match places
    ((Cons d rest) (match (act world (Build (Pylon) (offset world (Pair-first d) (Pair-second d)) #f))
                     ((Ok world) world)
                     ((Err _) (first-pylon world rest))))
    ((Nil) world)))

(: reinforce (-> World World))
(define (reinforce world)
  (let ((world (if (any? (lambda (b) (has-kind? (Some (Building-kind b)) (Pylon))) (World-buildings world))
                   world
                   (first-pylon world (list (Pair 3 0) (Pair -3 0) (Pair 0 3) (Pair 0 -3))))))
    (fold-left (lambda (world d) (try world (Build (Turret) (offset world (Pair-first d) (Pair-second d)) #f)))
               world (list (Pair -2 0) (Pair 0 2) (Pair 2 0) (Pair 0 -2) (Pair -2 2) (Pair 2 -2) (Pair 2 2) (Pair -2 -2)))))

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

;; ---- Staged enemies ----

;; Seed 3 with energy to spare, so rushed buildings are ready at once.
(: stage (-> World))
(define (stage)
  (earn (started (new-world 3)) 5000))

;; A sturdy enemy at `cell` that attacks whatever comes into sight with
;; the given percent chance.
(: staged-enemy (-> World Cell I64 I64 World))
(define (staged-enemy world cell rank aggression)
  (World-enemies-set world (list (Enemy 999 (Minion) rank #f aggression cell cell 2000 2000 (Nil) (None) (Plan -1 -1 #f)))))

(: the-enemy (-> World (Option Enemy)))
(define (the-enemy world)
  (find (lambda (e) (= (Enemy-id e) 999)) (World-enemies world)))

(: cell-text (-> Cell String))
(define (cell-text cell)
  (string-append (show (Cell-x cell)) "," (show (Cell-y cell))))

(: target-text (-> World Enemy String))
(define (target-text world enemy)
  (match (Enemy-target enemy)
    ((Some id) (match (building world id)
                 ((Some b) (string-append (kind-name (Building-kind b)) " at " (cell-text (Building-cell b))))
                 ((None) (match (worker world id) ((Some w) (string-append "worker " (show id))) ((None) "nothing")))))
    ((None) "the hub")))

;; What the enemy is doing whenever it changes its target, until `ticks`
;; have passed.
(: watch-targets (-> World I64 String Unit ! console))
(define (watch-targets world ticks last)
  (match (the-enemy world)
    ((Some enemy)
     (let ((now (target-text world enemy)))
       (unless (string=? now last)
         (write-line (string-append "  tick " (show (World-tick world)) ": at " (cell-text (Enemy-cell enemy)) ", going for " now)))
       (if (> ticks 0) (watch-targets (advance world) (- ticks 1) now) (unit))))
    ((None) (write-line (string-append "  tick " (show (World-tick world)) ": the enemy is gone")))))

;; Two pylons east of the hub, both in sight of an enemy that always
;; attacks. It takes the nearer first.
(let ()
  (define world (stage))
  (define world (try (try world (Build (Pylon) (Cell 45 39) #t)) (Build (Pylon) (Cell 47 41) #t)))
  (write-line "an aggressive enemy east of two pylons:")
  (watch-targets (staged-enemy world (Cell 50 40) 3 100) 400 ""))

;; A turret beside a pylon shoots a calm enemy from beyond its sight. The
;; enemy never rolls to attack it, so it keeps on for the hub.
(let ()
  (define world (stage))
  (define world (try (try world (Build (Pylon) (Cell 44 39) #t)) (Build (Turret) (Cell 45 39) #t)))
  (define world (staged-enemy world (Cell 51 39) 3 0))
  (write-line "a calm enemy shot by a turret:")
  (watch-targets world 100 "")
  (write-line (string-append "  by tick 100 it is at " (match (the-enemy (run world 100)) ((Some e) (string-append (cell-text (Enemy-cell e)) " with health " (show (Enemy-health e)))) ((None) "gone"))
                             ", the turret standing: " (show (match (building-at (run world 100) (Cell 45 39)) ((Some b) (= (Building-health b) 100)) ((None) #f))))))

;; Walls ring the hub two cells out. The enemy cannot walk in, so it plans
;; to dig, breaks a wall and strikes the hub.
(: ring (List (Pair I64 I64)))
(define ring
  (concatenate (list (map (lambda (i) (Pair (- i 2) -2)) (iota 5)) (map (lambda (i) (Pair (- i 2) 2)) (iota 5))
                     (map (lambda (i) (Pair -2 (- i 1))) (iota 3)) (map (lambda (i) (Pair 2 (- i 1))) (iota 3)))))

(: wall-health (-> World I64))
(define (wall-health world)
  (fold-left + 0 (map Building-health (filter wall? (World-buildings world)))))

(: watch-dig (-> World I64 Bool Unit ! console))
(define (watch-dig world ticks struck)
  (let ((hub (Hub-health (World-hub world))))
    (cond ((and (not struck) (< hub hub-health))
           (write-line (string-append "  tick " (show (World-tick world)) ": the hub is struck; walls standing " (show (length (filter wall? (World-buildings world))))))
           (watch-dig world ticks #t))
          ((> ticks 0) (watch-dig (advance world) (- ticks 1) struck))
          (else (unit)))))

(let ()
  (define world (stage))
  (define world (fold-left (lambda (world d) (try world (Build (Wall) (offset world (Pair-first d) (Pair-second d)) #t))) world ring))
  (write-line (string-append "walls around the hub: " (show (length (filter wall? (World-buildings world)))) ", their health " (show (wall-health world))))
  (define world (staged-enemy world (Cell 47 39) 0 0))
  (define world (run world 8))
  (write-line (string-append "  the enemy chose to dig: " (match (the-enemy world) ((Some e) (show (Plan-digging (Enemy-plan e)))) ((None) "gone"))))
  (define world (run world 60))
  (write-line (string-append "  tick " (show (World-tick world)) ": wall health " (show (wall-health world))))
  (watch-dig world 600 #f))

;; Workers beside an aggressive enemy strike back once a second.
(: watch-fight (-> World I64 Unit ! console))
(define (watch-fight world ticks)
  (when (= (remainder (World-tick world) 10) 0)
    (write-line (string-append "  tick " (show (World-tick world)) ": enemy " (match (the-enemy world) ((Some e) (show (Enemy-health e))) ((None) "gone"))
                               ", workers " (string-join (map (lambda (w) (show (Worker-health w))) (World-workers world)) " "))))
  (if (and (> ticks 0) (not (null? (World-enemies world)))) (watch-fight (advance world) (- ticks 1)) (unit)))

(let ()
  (define world (stage))
  (define world (World-enemies-set world (list (Enemy 999 (Minion) 0 #f 100 (Cell 42 38) (Cell 42 38) 65 65 (Nil) (None) (Plan -1 -1 #f)))))
  (write-line "workers beside an enemy:")
  (watch-fight world 120))
