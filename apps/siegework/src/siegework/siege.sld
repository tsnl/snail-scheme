;; The nests' side of the game, as in the original Siegework: escalating
;; waves from three fronts, raids on exposed outposts and a boss, enemies
;; that walk or burrow to the colony and strike it, turrets that shoot back,
;; and the outcome.
;;
;; Time is the world's tick. Waves, strength tiers and raids follow fixed
;; schedules; enemies step on multiples of their period and strike every
;; ten ticks; turrets fire every eight. No unit keeps a countdown.
(define-library (siegework siege)
  (export
   spawn
   excavate
   march
   fire
   strike
   settle
   judge
   enemy-period
   AttackKind
   Regular
   Raid
   Heavy
   attack-kind
   attack-size
   next-attack-tick
   attack-number
   difficulty-step
   difficulty-tier
   threat-tick
   living-nests)
  (import
   (snail core base)
   (siegework grid)
   (siegework terrain)
   (siegework world))
  (begin

    ;; ---- Schedule ----

    ;; A ten-minute expedition gets forty-five seconds before waves every
    ;; thirty seconds. Strength rises every ninety seconds; raids replace
    ;; every other wave from 1:45, and bosses come every nine minutes.
    (define wave-interval (→ I64) 300)

    (define first-wave (→ I64) 450)

    (define difficulty-step (→ I64) 900)

    (define first-raid (→ I64) 1050)

    (define raid-interval (→ I64) 600)

    (define boss-interval (→ I64) 5400)

    (define maximum-enemies (→ I64) 128)

    (enum AttackKind
      (Regular)
      (Raid)
      (Heavy))

    (define (heavy? (tick I64)) (→ Bool)
      (and (>= tick boss-interval) (= (remainder tick boss-interval) 0)))

    (define (raid? (tick I64)) (→ Bool)
      (and (>= tick first-raid) (= (remainder (- tick first-raid) raid-interval) 0)))

    (define (regular? (tick I64)) (→ Bool)
      (and (>= tick first-wave) (= (remainder (- tick first-wave) wave-interval) 0)))

    (define (attack-kind (tick I64)) (→ AttackKind)
      (cond ((heavy? tick) (Heavy))
            ((raid? tick) (Raid))
            (else (Regular))))

    ;; How many enemies attack at `tick`; zero when no attack is due. Sizes
    ;; grow more slowly than strength.
    (define (attack-size (tick I64)) (→ I64)
      (cond ((heavy? tick) (+ 12 (min 14 (quotient (- tick boss-interval) boss-interval))))
            ((raid? tick) (+ 11 (min 15 (quotient (- tick first-raid) raid-interval))))
            ((regular? tick) (+ 8 (min 18 (quotient (- tick first-wave) (* 3 difficulty-step)))))
            (else 0)))

    (define (next-attack-tick (tick I64)) (→ I64)
      (let loop ((candidate
                  (* (quotient wave-interval 2) (+ 1 (quotient tick (quotient wave-interval 2))))))
        (if (> (attack-size candidate) 0)
            candidate
            (loop (+ candidate (quotient wave-interval 2))))))

    ;; Attacks numbered from one; raids take regular slots and bosses fall
    ;; between them.
    (define (attack-number (tick I64)) (→ I64)
      (+ 1
         (+ (if (< tick first-wave) 0 (+ 1 (quotient (- tick first-wave) wave-interval)))
            (quotient tick boss-interval))))

    ;; ---- Strength ----

    ;; Strength rises a tier every ninety seconds, up to forty. Each cleared
    ;; nest takes back two tiers, after capping, so even a late clear helps.
    (define (threat-tick (world World)) (→ I64)
      (max 0
           (- (min (::tick world) (* 40 difficulty-step))
              (* (* 2 difficulty-step) (- 3 (length (living-nests world)))))))

    (define (difficulty-tier (tick I64)) (→ I64)
      (min 40 (quotient tick difficulty-step)))

    (define (rank-health (rank I64)) (→ I64)
      (case rank ((0) 65) ((1) 90) ((2) 125) ((3) 180) ((4) 300) ((5) 500) (else 1800)))

    (define (rank-damage (rank I64)) (→ I64)
      (case rank ((0) 7) ((1) 8) ((2) 10) ((3) 12) ((4) 16) ((5) 20) (else 30)))

    ;; The strongest enemy leads, a familiar rank follows, then mixed escorts.
    ;; The weakest rank stays common even after every rank unlocks.
    (define (wave-rank (rank I64) (index I64)) (→ I64)
      (cond ((= index 0) rank)
            ((or (= rank 0) (= (remainder index 3) 2)) 0)
            ((= index 1) (- rank 1))
            (else (remainder index rank))))

    ;; Past the last rank, tiers add health instead. Raiders are lighter.
    (define (spawn-health (world World) (behavior Behavior) (rank I64)) (→ I64)
      (let ((health
             (+ (rank-health rank) (* 15 (max 0 (- (difficulty-tier (threat-tick world)) 6))))))
        (match behavior
          ((Raider) (quotient (* 4 health) 5))
          (_ health))))

    (define (enemy-period (behavior Behavior)) (→ I64)
      (match behavior
        ((Raider) 6)
        (_ 8)))

    ;; ---- Spawning ----

    (define (living-nests (world World)) (→ (List Nest))
      (filter (lambda (nest) (> (::health nest) 0)) (::nests world)))

    ;; Each attack deals its enemies to the fronts in turn, starting where
    ;; the last one left off. A cleared front's share is skipped, never given
    ;; to the others.
    (define (spawn (world World)) (→ World)
      (let* ((tick (::tick world)) (size (attack-size tick)) (kind (attack-kind tick))
             (rank (min (match kind ((Heavy) 6) (_ 5)) (difficulty-tier (threat-tick world))))
             (shift (remainder (- (attack-number (- tick 1)) 1) 3)))
        (fold-left (lambda (world index) (spawn-one world kind size index rank shift))
                   world
                   (iota size))))

    ;; Each enemy leaves its nest by one of three lanes.
    (define (spawn-one (world World)
                       (kind AttackKind)
                       (size I64)
                       (index I64)
                       (rank I64)
                       (shift I64))
      (→ World)
      (let ((lane (+ 14 (* 2 (remainder (- size index) 3)))))
        (match (find (lambda (nest) (= (::front nest) (remainder (+ index shift) 3)))
                     (::nests world))
          ((Some nest)
           (if (or (= (::health nest) 0) (>= (length (::enemies world)) maximum-enemies))
               world
               (add-enemy world
                          nest
                          (wave-behavior world nest kind index lane)
                          lane
                          (wave-rank rank index))))
          ((None) world))))

    ;; A boss leads a heavy attack with ordinary escorts. Lanes that pass
    ;; rock beyond the nest breed raiders instead of minions.
    (define (wave-behavior (world World) (nest Nest) (kind AttackKind) (index I64) (lane I64))
      (→ Behavior)
      (match kind
        ((Heavy) (if (= index 0) (Beast) (lane-behavior world nest lane)))
        ((Raid) (Raider))
        ((Regular) (lane-behavior world nest lane))))

    (define (lane-behavior (world World) (nest Nest) (lane I64)) (→ Behavior)
      (let ((sample (Cell (+ (::x (::cell nest)) (if (= (remainder lane 3) 0) -12 12))
                          (+ (::y (::cell nest)) (- (remainder lane 5) 2)))))
        (if
         (and (in-bounds? sample) (match (ground-at (::land world) sample) ((Rock) #t) (_ #f)))
         (Raider)
         (Minion))))

    ;; About one enemy in ten burrows through rock.
    (define (add-enemy (world World) (nest Nest) (behavior Behavior) (lane I64) (rank I64))
      (→ World)
      (match (fresh-id world)
        ((Pair id world)
         (let* ((cell (Cell (+ (::x (::cell nest)) (- (remainder lane 3) 1))
                            (+ (::y (::cell nest)) 2)))
                (health (spawn-health world behavior rank))
                (burrower
                 (= (remainder (+ (remainder (::seed world) 10) (remainder id 10)) 10) 0)))
           (World-enemies-set world (append (::enemies world)
                                            (list (Enemy id
                                                         behavior
                                                         rank
                                                         burrower
                                                         cell
                                                         cell
                                                         health
                                                         health
                                                         (raid-target world nest behavior)
                                                         (None)))))))))

    ;; A raider picks the nearest exposed outpost on its own approach: a
    ;; finished extractor or pylon on the mainland, more than nine cells
    ;; from the hub and nearer this nest than the hub is. Without one it
    ;; attacks the hub.
    (define (raid-target (world World) (nest Nest) (behavior Behavior)) (→ (Option I64))
      (match behavior
        ((Raider)
         (let* ((hub (::cell (::hub world)))
                (front (::cell nest))
                (limit (manhattan front hub)))
           (match (nearest (filter (lambda (b)
                                     (and (exposed? b hub front limit)
                                          (mainland? (::land world) (::cell b))))
                                   (::buildings world))
                           (lambda (b) (manhattan front (::cell b))))
             ((Some b) (Some (::id b)))
             ((None) (None)))))
        (_ (None))))

    (define (exposed? (building Building) (hub Cell) (front Cell) (limit I64)) (→ Bool)
      (and (built? building) (match (::kind building) ((Turret) #f) (_ #t))
           (> (manhattan (::cell building) hub) 9)
           (< (manhattan front (::cell building)) limit)))

    ;; The first of the nearest, so ties go to the oldest.
    (define (nearest (items (List A)) (distance (dyn (Fn A → I64))))
      (→ (Option A))
      (∀ A)
      (⊨ (Copy A))
      (fold-left (lambda (best item)
                   (match best
                     ((Some other) (if (< (distance item) (distance other)) (Some item) best))
                     ((None) (Some item))))
                 (None) items))

    ;; ---- Routes ----

    ;; Walkers cross open ground, ice and opened rock; burrowers also cross
    ;; intact rock, which they dig through. Nobody crosses water. Each route is a
    ;; distance field toward a goal, kept until the terrain changes.
    (define (route-field (world World) (goal Cell) (burrower Bool)) (→ (Pair (Vector I64) World))
      (match (find (lambda (route)
                     (and (cell=? (::goal route) goal)
                          (eq-bool? (::burrower route) burrower)))
                   (::routes world))
        ((Some route) (Pair (::field route) world))
        ((None) (let ((field (distance-field (passable world burrower) (goal-cells world goal))))
                  (Pair field
                        (World-routes-set world
                                          (take
                                           (Cons (Route goal burrower field) (::routes world))
                                           8)))))))

    (define (eq-bool? (a Bool) (b Bool)) (→ Bool)
      (if a b (not b)))

    ;; The hub's goal is its whole footprint.
    (define (goal-cells (world World) (goal Cell)) (→ (List Cell))
      (let ((hub (::hub world)))
        (if (cell=? goal (::cell hub))
            (filter (lambda (cell) (hub-cell? hub cell))
                    (map (lambda (i)
                           (Cell (+ (::x goal) (- (remainder i 3) 1))
                                 (+ (::y goal) (- (quotient i 3) 1))))
                         (iota 9)))
            (list goal))))

    (define (passable (world World) (burrower Bool)) (→ (Vector Bool))
      (vector-generate (* map-size map-size)
                       (lambda (index)
                         (let ((cell (index-cell index)))
                           (match (ground-at (::land world) cell)
                             ((Rock) (or burrower (opened? world cell)))
                             ((Water) #f)
                             (_ #t))))))

    ;; ---- Movement ----

    (define (target-cell (world World) (enemy Enemy)) (→ Cell)
      (match (target-building world enemy)
        ((Some b) (::cell b))
        ((None) (::cell (::hub world)))))

    ;; The turret an enemy turned on while it stands, else the outpost it
    ;; raids while that stands; with neither it heads for the hub.
    (define (target-building (world World) (enemy Enemy)) (→ (Option Building))
      (match (standing world (::aggro enemy))
        ((Some b) (Some b))
        ((None) (standing world (::raid enemy)))))

    (define (standing (world World) (id (Option I64))) (→ (Option Building))
      (match id
        ((Some id)
         (match (building world id) ((Some b) (if (built? b) (Some b) (None))) ((None) (None))))
        ((None) (None))))

    ;; What an engaged enemy strikes.
    (enum Struck
      (StruckHub)
      (StruckBuilding ((building Building))))

    ;; An enemy stops beside its target and strikes it. One heading for the
    ;; hub stops beside the hub, or beside any finished building it meets.
    (define (engagement (world World) (enemy Enemy)) (→ (Option Struck))
      (let ((cell (::cell enemy)))
        (match (target-building world enemy)
          ((Some b) (if (beside? cell (::cell b)) (Some (StruckBuilding b)) (None)))
          ((None) (cond ((beside-hub? world cell) (Some (StruckHub)))
                        (else (match (beside-buildings world cell)
                                ((Cons b _) (Some (StruckBuilding b)))
                                ((Nil) (None)))))))))

    (define (engaged? (world World) (enemy Enemy)) (→ Bool)
      (match (engagement world enemy)
        ((Some _) #t)
        ((None) #f)))

    (define (beside? (a Cell) (b Cell)) (→ Bool)
      (<= (distance-squared a b) 1))

    (define (beside-hub? (world World) (cell Cell)) (→ Bool)
      (any? (lambda (neighbor) (hub-cell? (::hub world) neighbor))
            (Cons cell (neighbors cell))))

    (define (beside-buildings (world World) (cell Cell)) (→ (List Building))
      (filter (lambda (b) (and (built? b) (beside? cell (::cell b))))
              (::buildings world)))

    ;; The neighbor one step closer to the goal with the fewest enemies on
    ;; it, so crowds spread across parallel lanes.
    (define (next-cell (world World) (field (Vector I64)) (crowd (Vector I64)) (cell Cell))
      (→ (Option Cell))
      (let ((here (vector-ref field (cell-index cell))))
        (nearest
         (filter (lambda (n) (and (> here 0) (= (vector-ref field (cell-index n)) (- here 1))))
                 (neighbors cell))
         (lambda (n) (vector-ref crowd (cell-index n))))))

    (define (crowding (world World)) (→ (Vector I64))
      (unsafe-total
       (lambda ()
         (let ((counts (make-array (* map-size map-size) 0)))
           (for-each (lambda (e)
                       (array-set! counts
                                   (cell-index (::cell e))
                                   (+ 1 (array-ref counts (cell-index (::cell e))))))
                     (::enemies world))
           (array->vector counts)))))

    ;; On its period an enemy that is not engaged steps toward its target,
    ;; unless the step is into rock still being dug.
    (define (march (world World)) (→ World)
      (let ((crowd (crowding world)))
        (fold-left (lambda (world enemy) (if (on-step? world enemy) (step world crowd enemy) world))
                   world
                   (::enemies world))))

    (define (step (world World) (crowd (Vector I64)) (enemy Enemy)) (→ World)
      (let ((enemy (Enemy-previous-set enemy (::cell enemy))))
        (match (heading world crowd enemy)
          ((Pair (Some cell) world)
           (put-enemy world (if (walkable? world cell) (Enemy-cell-set enemy cell) enemy)))
          ((Pair (None) world) (put-enemy world enemy)))))

    ;; The next cell toward the enemy's target, if it is not engaged, with
    ;; the world holding the route it used.
    (define (heading (world World) (crowd (Vector I64)) (enemy Enemy))
      (→ (Pair (Option Cell) World))
      (if (engaged? world enemy)
          (Pair (None) world)
          (match (route-field world (target-cell world enemy) (::burrower enemy))
            ((Pair field world) (Pair (next-cell world field crowd (::cell enemy)) world)))))

    (define (walkable? (world World) (cell Cell)) (→ Bool)
      (match (ground-at (::land world) cell)
        ((Rock) (opened? world cell))
        ((Water) #f)
        (_ #t)))

    (define (on-step? (world World) (enemy Enemy)) (→ Bool)
      (= (remainder (+ (::tick world) (::id enemy)) (enemy-period (::behavior enemy)))
         0))

    (define (put-enemy (world World) (enemy Enemy)) (→ World)
      (World-enemies-set world
                         (map (lambda (e) (if (= (::id e) (::id enemy)) enemy e))
                              (::enemies world))))

    ;; ---- Excavation ----

    ;; A burrower facing intact rock chips it, one point a tick, with at most
    ;; two working on a cell: even a crowd needs four seconds to open one.
    (define (excavate (world World)) (→ World)
      (match (dig-faces world)
        ((Pair faces world)
         (fold-left (lambda (world cell)
                      (chip world
                            cell
                            (min 2 (length (filter (lambda (c) (cell=? c cell)) faces)))))
                    world (delete-duplicates cell=? faces)))))

    ;; The rock each burrower is about to dig into.
    (define (dig-faces (world World)) (→ (Pair (List Cell) World))
      (let ((crowd (crowding world)))
        (fold-left (lambda (found enemy)
                     (match (heading (::second found) crowd enemy)
                       ((Pair (Some cell) world)
                        (Pair (if (walkable? world cell)
                                  (::first found)
                                  (Cons cell (::first found)))
                              world))
                       ((Pair (None) world) (Pair (::first found) world))))
                   (Pair (Nil) world) (filter ::burrower (::enemies world)))))

    (define (chip (world World) (cell Cell) (amount I64)) (→ World)
      (let ((remaining (- (match (find (lambda (d) (cell=? (::cell d) cell)) (::digs world))
                            ((Some d) (::remaining d))
                            ((None) rock-health))
                          amount))
            (others (filter (lambda (d) (not (cell=? (::cell d) cell))) (::digs world))))
        (if (<= remaining 0)
            (open-rock (World-digs-set world others) cell)
            (World-digs-set world (Cons (Dig cell remaining) others)))))

    ;; ---- Turrets ----

    ;; A powered turret fires every eight ticks at the nearest visible enemy
    ;; in range and in line of sight, so it deals first with what is doing
    ;; damage close by; without one it fires at a nest in range. The enemy
    ;; it hits may turn on it.
    (define (fire (world World)) (→ World)
      (fold-left fire-one
                 world
                 (filter (lambda (b) (and (turret? b) (built? b) (powered? world (::id b))
                                          (= (remainder (+ (::tick world) (::id b)) 8)
                                             0)))
                         (::buildings world))))

    (define (turret? (b Building)) (→ Bool)
      (match (::kind b) ((Turret) #t) (_ #f)))

    (define (fire-one (world World) (turret Building)) (→ World)
      (match (choose-enemy world turret)
        ((Some enemy) (hit-enemy world turret enemy))
        ((None)
         (match (find (lambda (nest) (can-shoot? world turret (::cell nest)))
                      (living-nests world))
           ((Some nest) (hit-nest world turret nest))
           ((None) world)))))

    (define (can-shoot? (world World) (turret Building) (cell Cell)) (→ Bool)
      (and (visible? world cell)
           (within? cell (::cell turret) 6)
           (clear-line? world (::cell turret) cell)))

    ;; The nearest enemy the turret can shoot; ties go to the oldest.
    (define (choose-enemy (world World) (turret Building)) (→ (Option Enemy))
      (nearest (filter (lambda (e) (can-shoot? world turret (::cell e))) (::enemies world))
               (lambda (e) (distance-squared (::cell e) (::cell turret)))))

    ;; Damage falls from 24 at point blank to 6 at the six-cell range,
    ;; measured in fortieths of a cell, and grows with the turret's level:
    ;; one, one and a half, then two times.
    (define (damage (turret Building) (cell Cell)) (→ I64)
      (let ((length (integer-sqrt (* 1600 (distance-squared cell (::cell turret))))))
        (quotient (* (+ 6 (quotient (* 18 (- 240 length)) 240)) (+ (::level turret) 1)) 2)))

    (define (hit-enemy (world World) (turret Building) (enemy Enemy)) (→ World)
      (let ((wounded
             (Enemy-health-set enemy (- (::health enemy) (damage turret (::cell enemy))))))
        (shoot
         (put-enemy world (if (> (::health wounded) 0) (provoke world wounded turret) wounded))
         turret (::cell enemy))))

    ;; A wounded enemy turns on the turret that hit it unless the one it
    ;; already turned on still stands, so turrets on both sides of it cannot
    ;; pull it back and forth. A turret across water is out of its reach,
    ;; and it keeps on its way.
    (define (provoke (world World) (enemy Enemy) (turret Building)) (→ Enemy)
      (match (standing world (::aggro enemy))
        ((Some _) enemy)
        ((None)
         (if (mainland? (::land world) (::cell turret))
             (Enemy-aggro-set enemy (Some (::id turret)))
             enemy))))

    ;; A destroyed nest changes the structures: its crystal shows instead.
    (define (hit-nest (world World) (turret Building) (nest Nest)) (→ World)
      (let* ((health (max 0 (- (::health nest) (damage turret (::cell nest)))))
             (world (World-nests-set world
                                     (map (lambda (n)
                                            (if (= (::front n) (::front nest))
                                                (Nest-health-set n health)
                                                n))
                                          (::nests world)))))
        (shoot (if (= health 0) (structures-changed world) world) turret (::cell nest))))

    ;; A shot leaves a tracer and turns the turret's guns to where it went.
    (define (shoot (world World) (turret Building) (cell Cell)) (→ World)
      (World-buildings-set (World-shots-set world
                                            (Cons
                                             (Shot (::cell turret) cell (::tick world))
                                             (::shots world)))
                           (map (lambda (b)
                                  (if (= (::id b) (::id turret))
                                      (Building-aim-set b (Some cell))
                                      b))
                                (::buildings world))))

    ;; ---- Strikes ----

    ;; Every ten ticks each engaged enemy strikes for its rank's damage.
    (define (strike (world World)) (→ World)
      (if (= (remainder (::tick world) 10) 0)
          (fold-left strike-one world (::enemies world))
          world))

    (define (strike-one (world World) (enemy Enemy)) (→ World)
      (match (engagement world enemy)
        ((Some (StruckHub)) (damage-hub world (rank-damage (::rank enemy))))
        ((Some (StruckBuilding b)) (damage-building world b (rank-damage (::rank enemy))))
        ((None) world)))

    (define (damage-building (world World) (b Building) (amount I64)) (→ World)
      (alert (put-building world (Building-health-set b (max 0 (- (::health b) amount))))
             (::cell b)))

    (define (damage-hub (world World) (amount I64)) (→ World)
      (let ((hub (::hub world)))
        (alert (World-hub-set world (Hub-health-set hub (max 0 (- (::health hub) amount))))
               (::cell hub))))

    ;; At most four alerts: a new one replaces any within four cells and any
    ;; older than eight seconds.
    (define (alert (world World) (cell Cell)) (→ World)
      (let ((tick (::tick world)))
        (World-alerts-set world (Cons (Alert cell tick)
                                      (take (filter (lambda (a)
                                                      (and (<= (- tick (::tick a)) 80)
                                                           (not (within? (::cell a) cell 4))))
                                                    (::alerts world))
                                            3)))))

    ;; ---- Settling ----

    ;; Removes the dead and destroyed, counts them, and drops old shots.
    (define (settle (world World)) (→ World)
      (let* ((alive (filter (lambda (e) (> (::health e) 0)) (::enemies world)))
             (standing (filter (lambda (b) (> (::health b) 0)) (::buildings world)))
             (world (count-losses world
                                  (- (length (::enemies world)) (length alive))
                                  (- (length (::buildings world)) (length standing))))
             (world (World-shots-set (World-enemies-set world alive)
                                     (filter (lambda (s) (> (+ (::tick s) 4) (::tick world)))
                                             (::shots world)))))
        (if (= (length standing) (length (::buildings world)))
            world
            (rewire (World-buildings-set world standing)))))

    (define (count-losses (world World) (kills I64) (lost I64)) (→ World)
      (let ((ledger (::ledger world)))
        (World-ledger-set world
                          (Ledger-lost-set (Ledger-kills-set ledger (+ (::kills ledger) kills))
                                           (+ (::lost ledger) lost)))))

    ;; Destroying every nest wins, even on the tick the hub falls. Either way
    ;; the whole map is uncovered for inspection.
    (define (judge (world World)) (→ World)
      (cond ((null? (living-nests world)) (uncover (World-outcome-set world (Won))))
            ((= (::health (::hub world)) 0) (uncover (World-outcome-set world (Lost))))
            (else world)))

    ))
