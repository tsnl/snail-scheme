;; The nests' side of the game: waves, enemies walking to the colony and
;; striking it, turrets shooting back, and the outcome.
(define-library (siegework siege)
  (export
   spawn-waves
   update-enemies
   fire-turrets
   clean-up
   judge
   ticks-until-wave
   enemy-period)
  (import
   (lofi base)
   (siegework grid)
   (siegework terrain)
   (siegework world))
  (begin

    ;; ---- Waves ----

    (: enemy-period I64)
    (define enemy-period 5)

    (: first-wave I64)
    (define first-wave 600)

    (: wave-interval I64)
    (define wave-interval 300)

    (: on-period? (-> World I64 Bool))
    (define (on-period? world period)
      (= (remainder (World-tick world) period) 0))

    (: ticks-until-wave (-> World I64))
    (define (ticks-until-wave world)
      (let ((tick (World-tick world)))
        (if (< tick first-wave)
            (- first-wave tick)
            (- wave-interval (remainder (- tick first-wave) wave-interval)))))

    (: living-nests (-> World (List Nest)))
    (define (living-nests world)
      (filter (lambda (nest) (> (Nest-health nest) 0)) (World-nests world)))

    ;; Wave n sends min(8, n) enemies from each living nest, each with
    ;; 30 + 10n health.
    (: spawn-waves (-> World World))
    (define (spawn-waves world)
      (let ((tick (World-tick world)))
        (if (and (>= tick first-wave) (= (remainder (- tick first-wave) wave-interval) 0))
            (let ((wave (+ 1 (quotient (- tick first-wave) wave-interval))))
              (fold-left (lambda (world nest)
                           (fold-left (lambda (world index) (spawn world (Nest-cell nest) (+ 30 (* 10 wave)))) world (iota (min 8 wave))))
                         world (living-nests world)))
            world)))

    (: spawn (-> World Cell I64 World))
    (define (spawn world cell health)
      (match (fresh-id world)
        ((Pair id world) (World-enemies-set world (Cons (Enemy id (Mover cell cell (Nil)) health (None)) (World-enemies world))))))

    ;; ---- Enemies ----

    (: walk (-> World Mover Mover))
    (define (walk world mover)
      (cond ((not (on-period? world enemy-period)) mover)
            (else (match (Mover-path mover)
                    ((Nil) (Mover-previous-set mover (Mover-cell mover)))
                    ((Cons next rest) (Mover next (Mover-cell mover) rest))))))

    (: open-cells (-> World (Vector Bool)))
    (define (open-cells world)
      (vector-map (lambda (ground) (match ground ((Grass) #t) (_ #f))) (Land-ground (World-land world))))

    ;; An enemy walks to the nearest building or the hub and strikes it every
    ;; ten ticks once it stands on it; a lost target is replaced.
    (: update-enemies (-> World World))
    (define (update-enemies world)
      (let ((open (open-cells world)))
        (fold-left (lambda (world enemy) (update-enemy world open enemy)) world (World-enemies world))))

    (: update-enemy (-> World (Vector Bool) Enemy World))
    (define (update-enemy world open enemy)
      (let* ((enemy (if (target-exists? world enemy) enemy (retarget world open enemy)))
             (enemy (Enemy-mover-set enemy (walk world (Enemy-mover enemy))))
             (world (put-enemy world enemy)))
        (if (and (null? (Mover-path (Enemy-mover enemy))) (on-period? world 10)) (strike world enemy) world)))

    (: target-exists? (-> World Enemy Bool))
    (define (target-exists? world enemy)
      (match (Enemy-target enemy)
        ((Some id) (match (building world id) ((Some _) #t) ((None) #f)))
        ((None) (not (null? (Mover-path (Enemy-mover enemy)))))))

    (: put-enemy (-> World Enemy World))
    (define (put-enemy world enemy)
      (World-enemies-set world (map (lambda (e) (if (= (Enemy-id e) (Enemy-id enemy)) enemy e)) (World-enemies world))))

    ;; One search finds both the nearest target and the way to it.
    (: retarget (-> World (Vector Bool) Enemy Enemy))
    (define (retarget world open enemy)
      (let* ((start (Mover-cell (Enemy-mover enemy)))
             (goal? (lambda (cell) (or (hub-cell? (World-hub world) cell) (any? (lambda (b) (cell=? (Building-cell b) cell)) (World-buildings world))))))
        (match (find-path open start goal?)
          ((Some path)
           (let ((goal (match (last path) ((Some cell) cell) ((None) start))))
             (Enemy-target-set (Enemy-mover-set enemy (Mover-path-set (Enemy-mover enemy) path))
                               (match (building-at world goal) ((Some b) (Some (Building-id b))) ((None) (None))))))
          ((None) (Enemy-target-set enemy (None))))))

    (: strike (-> World Enemy World))
    (define (strike world enemy)
      (let ((cell (Mover-cell (Enemy-mover enemy))))
        (cond ((hub-cell? (World-hub world) cell)
               (World-hub-set world (Hub-health-set (World-hub world) (- (Hub-health (World-hub world)) 6))))
              (else (match (building-at world cell)
                      ((Some b) (put-building world (Building-health-set b (- (Building-health b) 6))))
                      ((None) world))))))

    ;; ---- Turrets ----

    ;; Every eight ticks a powered turret hits the nearest enemy within six
    ;; cells, harder at higher levels, or else a nest within six cells.
    (: fire-turrets (-> World World))
    (define (fire-turrets world)
      (if (on-period? world 8)
          (fold-left fire world (filter (lambda (b) (and (built? b) (match (Building-kind b) ((Turret) #t) (_ #f)) (powered? world (Building-id b))))
                                        (World-buildings world)))
          world))

    (: fire (-> World Building World))
    (define (fire world turret)
      (let* ((cell (Building-cell turret)) (in-range? (lambda (target) (within? cell target 6)))
             (damage (quotient (* 25 (+ (Building-level turret) 1)) 2)))
        (match (nearest (filter (lambda (e) (in-range? (Mover-cell (Enemy-mover e)))) (World-enemies world))
                        (lambda (e) (distance-squared cell (Mover-cell (Enemy-mover e)))))
          ((Some enemy) (shoot (put-enemy world (Enemy-health-set enemy (- (Enemy-health enemy) damage))) cell (Mover-cell (Enemy-mover enemy))))
          ((None) (match (find (lambda (n) (and (> (Nest-health n) 0) (in-range? (Nest-cell n)))) (World-nests world))
                    ((Some nest) (shoot (hurt-nest world nest damage) cell (Nest-cell nest)))
                    ((None) world))))))

    (: hurt-nest (-> World Nest I64 World))
    (define (hurt-nest world nest damage)
      (structures-changed
       (World-nests-set world (map (lambda (n) (if (= (Nest-front n) (Nest-front nest)) (Nest-health-set n (max 0 (- (Nest-health n) damage))) n))
                                   (World-nests world)))))

    (: shoot (-> World Cell Cell World))
    (define (shoot world from to)
      (World-shots-set world (Cons (Shot from to (World-tick world)) (World-shots world))))

    (: nearest (All (A) (-> (List A) (-> A I64) (Option A))))
    (define (nearest items distance)
      (fold-left (lambda (best item)
                   (match best
                     ((Some other) (if (< (distance item) (distance other)) (Some item) best))
                     ((None) (Some item))))
                 (None) items))

    ;; ---- Ticks ----

    ;; Removes the dead, the destroyed and old shots.
    (: clean-up (-> World World))
    (define (clean-up world)
      (let* ((alive (filter (lambda (e) (> (Enemy-health e) 0)) (World-enemies world)))
             (standing (filter (lambda (b) (> (Building-health b) 0)) (World-buildings world)))
             (ledger (World-ledger world))
             (world (World-ledger-set (World-enemies-set world alive)
                                      (Ledger-lost-set (Ledger-kills-set ledger (+ (Ledger-kills ledger) (- (length (World-enemies world)) (length alive))))
                                                       (+ (Ledger-lost ledger) (- (length (World-buildings world)) (length standing))))))
             (world (World-shots-set world (filter (lambda (s) (> (+ (Shot-tick s) 4) (World-tick world))) (World-shots world)))))
        (if (= (length standing) (length (World-buildings world))) world (rewire (World-buildings-set world standing)))))

    ;; Destroying every nest wins, even on the tick the hub falls.
    (: judge (-> World World))
    (define (judge world)
      (cond ((null? (living-nests world)) (World-outcome-set world (Won)))
            ((<= (Hub-health (World-hub world)) 0) (World-outcome-set world (Lost)))
            (else world)))

    ))
