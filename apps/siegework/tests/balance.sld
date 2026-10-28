;; Balance invariants, checked on eight seeds covering every biome so that
;; tuning the numbers cannot quietly break the game:
;;
;; - an extractor and a turret ordered together are both finished before
;;   the first attack leaves the nests;
;; - a hub left undefended falls within 55 seconds of the first attack
;;   leaving the nests, even where the way in winds over causeways;
;; - a colony that keeps adding turrets around its hub, and widens its build
;;   slots when it can, holds for five minutes.
;;
;; Each check prints #t, or the seeds that break it.
(import
 (snail-core base)
 (snail-core io)
 (siegework grid)
 (only (siegework terrain) Land-starter)
 (siegework world)
 (siegework colony)
 (siegework siege)
 (siegework simulation))

(: seeds (List I64))
(define seeds (list 1 2 3 4 5 6 7 8))

(: run (-> World I64 World))
(define (run world ticks)
  (if (or (= ticks 0) (not (playing? world))) world (run (advance world) (- ticks 1))))

(: try (-> World Action World))
(define (try world action)
  (match (act world action)
    ((Ok world) world)
    ((Err _) world)))

(: offset (-> World I64 I64 Cell))
(define (offset world dx dy)
  (let ((hub (Hub-cell (World-hub world))))
    (Cell (+ (Cell-x hub) dx) (+ (Cell-y hub) dy))))

(: started (-> I64 World))
(define (started seed)
  (let ((world (new-world seed)))
    (try world (Build (Extractor) (Land-starter (World-land world)) #f))))

(: reinforce (-> World World))
(define (reinforce world)
  (try (fold-left (lambda (world d)
                    (try world (Build (Turret) (offset world (Pair-first d) (Pair-second d)) #f)))
                  world
                  (list (Pair -2 0)
                        (Pair 0 2)
                        (Pair 2 0)
                        (Pair 0 -2)
                        (Pair -2 2)
                        (Pair 2 -2)
                        (Pair 2 2)
                        (Pair -2 -2)))
       (Upgrade (offset world 0 0))))

(: defend (-> World I64 World))
(define (defend world ticks)
  (if (or (<= ticks 0) (not (playing? world)))
      world
      (defend (run (reinforce world) 100) (- ticks 100))))

(: built-count (-> World I64))
(define (built-count world)
  (length (filter built? (World-buildings world))))

(: ready-for-first-attack? (-> I64 Bool))
(define (ready-for-first-attack? seed)
  (let ((world (started seed)))
    (= (built-count
        (run (try world (Build (Turret) (offset world -2 0) #f)) (- (next-attack-tick 0) 1)))
       2)))

(: undefended-falls? (-> I64 Bool))
(define (undefended-falls? seed)
  (match (World-outcome (run (started seed) 1000))
    ((Lost) #t)
    (_ #f)))

(: defended-holds? (-> I64 Bool))
(define (defended-holds? seed)
  (let ((world (defend (started seed) 3000)))
    (and (playing? world) (= (World-tick world) 3000))))

(: check (-> String (-> I64 Bool) Unit ! console))
(define (check claim holds?)
  (let ((broken (filter (lambda (seed) (not (holds? seed))) seeds)))
    (write-line (string-append claim
                               ": "
                               (if (null? broken)
                                   "#t"
                                   (string-append "broken on seeds "
                                                  (string-join (map show broken) " ")))))))

(check "an extractor and a turret are ready before the first attack" ready-for-first-attack?)
(check "an undefended hub falls before tick 1000" undefended-falls?)
(check "a hub ringed with turrets holds through tick 3000" defended-holds?)
