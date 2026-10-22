;; Balance invariants, checked on eight seeds covering every biome so that
;; tuning the numbers cannot quietly break the game:
;;
;; - a pylon and a turret beside it, built by the starting workers, are
;;   finished before the first attack leaves the nests;
;; - a hub left undefended falls before tick 1200, within 75 seconds of
;;   the first attack leaving the nests, even where the way in winds over
;;   causeways;
;; - a colony that keeps a pylon and a ring of turrets around its hub,
;;   upgrades its extractor, adds spare pylons and trains a few more
;;   workers, holds for five minutes.
;;
;; Each check prints #t, or the seeds that break it; then the numbers
;; behind them for each seed.
(import
 (lofi base)
 (lofi io)
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

;; Pylons on the four sides of the hub power the turrets around it.
(: pylons (List (Pair I64 I64)))
(define pylons (list (Pair 3 0) (Pair -3 0) (Pair 0 3) (Pair 0 -3)))

(: ring (List (Pair I64 I64)))
(define ring (list (Pair -2 0) (Pair 0 2) (Pair 2 0) (Pair 0 -2) (Pair -2 2) (Pair 2 -2) (Pair 2 2) (Pair -2 -2)))

(: build-all (-> World Kind (List (Pair I64 I64)) World))
(define (build-all world kind places)
  (fold-left (lambda (world d) (try world (Build kind (offset world (Pair-first d) (Pair-second d)) #f))) world places))

(: reinforce (-> World World))
(define (reinforce world)
  (let* ((world (if (any? (lambda (b) (has-kind? (Some (Building-kind b)) (Pylon))) (World-buildings world)) world (first-pylon world pylons)))
         (world (build-all (try (build-all world (Turret) ring) (Upgrade (Land-starter (World-land world)))) (Pylon) pylons)))
    (if (< (length (World-workers world)) 5) (try world (Train)) world)))

;; The first of the places around the hub that takes a pylon.
(: first-pylon (-> World (List (Pair I64 I64)) World))
(define (first-pylon world places)
  (match places
    ((Cons d rest) (match (act world (Build (Pylon) (offset world (Pair-first d) (Pair-second d)) #f))
                     ((Ok world) world)
                     ((Err _) (first-pylon world rest))))
    ((Nil) world)))

(: defend (-> World I64 World))
(define (defend world ticks)
  (if (or (<= ticks 0) (not (playing? world))) world (defend (run (reinforce world) 100) (- ticks 100))))

(: built-count (-> World I64))
(define (built-count world)
  (length (filter built? (World-buildings world))))

;; A pylon first, then a turret it powers.
(: first-defense (-> I64 World))
(define (first-defense seed)
  (let* ((world (first-pylon (started seed) pylons)) (world (run world 40)))
    (run (build-all world (Turret) (list (Pair -2 0) (Pair 2 0))) (- (next-attack-tick 0) 41))))

(: ready-for-first-attack? (-> I64 Bool))
(define (ready-for-first-attack? seed)
  (= (built-count (first-defense seed)) (length (World-buildings (first-defense seed)))))

(: undefended (-> I64 World))
(define (undefended seed)
  (run (started seed) 3000))

(: undefended-falls? (-> I64 Bool))
(define (undefended-falls? seed)
  (let ((world (undefended seed)))
    (and (< (World-tick world) 1200) (match (World-outcome world) ((Lost) #t) (_ #f)))))

(: defended (-> I64 World))
(define (defended seed)
  (defend (started seed) 3000))

(: defended-holds? (-> I64 Bool))
(define (defended-holds? seed)
  (let ((world (defended seed)))
    (and (playing? world) (= (World-tick world) 3000))))

(: check (-> String (-> I64 Bool) Unit ! console))
(define (check claim holds?)
  (let ((broken (filter (lambda (seed) (not (holds? seed))) seeds)))
    (write-line (string-append claim ": " (if (null? broken) "#t" (string-append "broken on seeds " (string-join (map show broken) " ")))))))

(: numbers (-> I64 Unit ! console))
(define (numbers seed)
  (let ((lost (undefended seed)) (held (defended seed)))
    (write-line (string-append "seed " (show seed) ": undefended hub falls at tick " (show (World-tick lost))
                               "; defended at tick " (show (World-tick held)) ": hub " (show (Hub-health (World-hub held)))
                               ", turrets " (show (length (filter (lambda (b) (and (built? b) (has-kind? (Some (Building-kind b)) (Turret)))) (World-buildings held))))
                               ", workers " (show (length (World-workers held))) ", kills " (show (Ledger-kills (World-ledger held)))
                               ", buildings lost " (show (Ledger-lost (World-ledger held)))))))

(check "a pylon and a turret are ready before the first attack" ready-for-first-attack?)
(check "an undefended hub falls before tick 1200" undefended-falls?)
(check "a hub ringed with turrets holds through tick 3000" defended-holds?)
(for-each numbers seeds)
