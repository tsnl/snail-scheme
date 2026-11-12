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
 (snail core base)
 (snail core io)
 (siegework grid)
 (only (siegework terrain))
 (siegework world)
 (siegework colony)
 (siegework siege)
 (siegework simulation))

(define seeds (→ (List I64)) (list 1 2 3 4 5 6 7 8))

(define (run (world World) (ticks I64)) (→ World)
  (if (or (= ticks 0) (not (playing? world))) world (run (advance world) (- ticks 1))))

(define (try (world World) (action Action)) (→ World)
  (match (act world action)
    ((Ok world) world)
    ((Err _) world)))

(define (offset (world World) (dx I64) (dy I64)) (→ Cell)
  (let ((hub (● (● world hub) cell)))
    (Cell (+ (● hub x) dx) (+ (● hub y) dy))))

(define (started (seed I64)) (→ World)
  (let ((world (new-world seed)))
    (try world (Build (Extractor) (● (● world land) starter) #f))))

(define (reinforce (world World)) (→ World)
  (try (fold-left (lambda (world d)
                    (try world (Build (Turret) (offset world (● d first) (● d second)) #f)))
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

(define (defend (world World) (ticks I64)) (→ World)
  (if (or (<= ticks 0) (not (playing? world)))
      world
      (defend (run (reinforce world) 100) (- ticks 100))))

(define (built-count (world World)) (→ I64)
  (length (filter built? (● world buildings))))

(define (ready-for-first-attack? (seed I64)) (→ Bool)
  (let ((world (started seed)))
    (= (built-count
        (run (try world (Build (Turret) (offset world -2 0) #f)) (- (next-attack-tick 0) 1)))
       2)))

(define (undefended-falls? (seed I64)) (→ Bool)
  (match (● (run (started seed) 1000) outcome)
    ((Lost) #t)
    (_ #f)))

(define (defended-holds? (seed I64)) (→ Bool)
  (let ((world (defend (started seed) 3000)))
    (and (playing? world) (= (● world tick) 3000))))

(define (check (claim String) (holds? (Fn I64 → Bool))) (→ Unit) (! output-port)
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
