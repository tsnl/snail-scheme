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
   (snail-core base)
   (siegework grid)
   (siegework terrain)
   (siegework world))
  (begin

    ;; ---- Schedule ----

    ;; A ten-minute expedition gets forty-five seconds before waves every
    ;; thirty seconds. Strength rises every ninety seconds; raids replace
    ;; every other wave from 1:45, and bosses come every nine minutes.
    (: wave-interval I64)
    (define wave-interval 300)

    (: first-wave I64)
    (define first-wave 450)

    (: difficulty-step I64)
    (define difficulty-step 900)

    (: first-raid I64)
    (define first-raid 1050)

    (: raid-interval I64)
    (define raid-interval 600)

    (: boss-interval I64)
    (define boss-interval 5400)

    (: maximum-enemies I64)
    (define maximum-enemies 128)

    (enum AttackKind
      (Regular)
      (Raid)
      (Heavy))

    (: heavy? (-> I64 Bool))
    (define (heavy? tick)
      (and (>= tick boss-interval) (= (remainder tick boss-interval) 0)))

    (: raid? (-> I64 Bool))
    (define (raid? tick)
      (and (>= tick first-raid)
           (= (remainder (- tick first-raid) raid-interval) 0)))

    (: regular? (-> I64 Bool))
    (define (regular? tick)
      (and (>= tick first-wave)
           (= (remainder (- tick first-wave) wave-interval) 0)))

    (: attack-kind (-> I64 AttackKind))
    (define (attack-kind tick)
      (cond ((heavy? tick) (Heavy))
            ((raid? tick) (Raid))
            (else (Regular))))

    ;; How many enemies attack at `tick`; zero when no attack is due. Sizes
    ;; grow more slowly than strength.
    (: attack-size (-> I64 I64))
    (define (attack-size tick)
      (cond ((heavy? tick)
             (+ 12 (min 14 (quotient (- tick boss-interval) boss-interval))))
            ((raid? tick)
             (+ 11 (min 15 (quotient (- tick first-raid) raid-interval))))
            ((regular? tick)
             (+ 8
                (min 18 (quotient (- tick first-wave) (* 3 difficulty-step)))))
            (else 0)))

    (: next-attack-tick (-> I64 I64))
    (define (next-attack-tick tick)
      (let loop ((candidate (* (quotient wave-interval 2)
                               (+ 1
                                  (quotient tick (quotient wave-interval 2))))))
        (if (> (attack-size candidate) 0)
            candidate
            (loop (+ candidate (quotient wave-interval 2))))))

    ;; Attacks numbered from one; raids take regular slots and bosses fall
    ;; between them.
    (: attack-number (-> I64 I64))
    (define (attack-number tick)
      (+ 1
         (+ (if (< tick first-wave)
                0
                (+ 1 (quotient (- tick first-wave) wave-interval)))
            (quotient tick boss-interval))))

    ;; ---- Strength ----

    ;; Strength rises a tier every ninety seconds, up to forty. Each cleared
    ;; nest takes back two tiers, after capping, so even a late clear helps.
    (: threat-tick (-> World I64))
    (define (threat-tick world)
      (max 0
           (- (min (World-tick world) (* 40 difficulty-step))
              (* (* 2 difficulty-step) (- 3 (length (living-nests world)))))))

    (: difficulty-tier (-> I64 I64))
    (define (difficulty-tier tick)
      (min 40 (quotient tick difficulty-step)))

    (: rank-health (-> I64 I64))
    (define (rank-health rank)
      (case rank
        ((0) 65)
        ((1) 90)
        ((2) 125)
        ((3) 180)
        ((4) 300)
        ((5) 500)
        (else 1800)))

    (: rank-damage (-> I64 I64))
    (define (rank-damage rank)
      (case rank ((0) 7) ((1) 8) ((2) 10) ((3) 12) ((4) 16) ((5) 20) (else 30)))

    ;; The strongest enemy leads, a familiar rank follows, then mixed escorts.
    ;; The weakest rank stays common even after every rank unlocks.
    (: wave-rank (-> I64 I64 I64))
    (define (wave-rank rank index)
      (cond ((= index 0) rank)
            ((or (= rank 0) (= (remainder index 3) 2)) 0)
            ((= index 1) (- rank 1))
            (else (remainder index rank))))

    ;; Past the last rank, tiers add health instead. Raiders are lighter.
    (: spawn-health (-> World Behavior I64 I64))
    (define (spawn-health world behavior rank)
      (let ((health (+ (rank-health rank)
                       (* 15
                          (max 0
                               (- (difficulty-tier (threat-tick world)) 6))))))
        (match behavior
          ((Raider) (quotient (* 4 health) 5))
          (_ health))))

    (: enemy-period (-> Behavior I64))
    (define (enemy-period behavior)
      (match behavior
        ((Raider) 6)
        (_ 8)))

    ;; ---- Spawning ----

    (: living-nests (-> World (List Nest)))
    (define (living-nests world)
      (filter (lambda (nest) (> (Nest-health nest) 0)) (World-nests world)))

    ;; Each attack deals its enemies to the fronts in turn, starting where
    ;; the last one left off. A cleared front's share is skipped, never given
    ;; to the others.
    (: spawn (-> World World))
    (define (spawn world)
      (let* ((tick (World-tick world))
             (size (attack-size tick))
             (kind (attack-kind tick))
             (rank (min (match kind ((Heavy) 6) (_ 5))
                        (difficulty-tier (threat-tick world))))
             (shift (remainder (- (attack-number (- tick 1)) 1) 3)))
        (fold-left
         (lambda (world index) (spawn-one world kind size index rank shift))
         world
         (iota size))))

    ;; Each enemy leaves its nest by one of three lanes.
    (: spawn-one (-> World AttackKind I64 I64 I64 I64 World))
    (define (spawn-one world kind size index rank shift)
      (let ((lane (+ 14 (* 2 (remainder (- size index) 3)))))
        (match (find (lambda (nest)
                       (= (Nest-front nest) (remainder (+ index shift) 3)))
                     (World-nests world))
          ((Some nest)
           (if (or (= (Nest-health nest) 0)
                   (>= (length (World-enemies world)) maximum-enemies))
               world
               (add-enemy world
                          nest
                          (wave-behavior world nest kind index lane)
                          lane
                          (wave-rank rank index))))
          ((None) world))))

    ;; A boss leads a heavy attack with ordinary escorts. Lanes that pass
    ;; rock beyond the nest breed raiders instead of minions.
    (: wave-behavior (-> World Nest AttackKind I64 I64 Behavior))
    (define (wave-behavior world nest kind index lane)
      (match kind
        ((Heavy) (if (= index 0) (Beast) (lane-behavior world nest lane)))
        ((Raid) (Raider))
        ((Regular) (lane-behavior world nest lane))))

    (: lane-behavior (-> World Nest I64 Behavior))
    (define (lane-behavior world nest lane)
      (let ((sample (Cell (+ (Cell-x (Nest-cell nest))
                             (if (= (remainder lane 3) 0) -12 12))
                          (+ (Cell-y (Nest-cell nest))
                             (- (remainder lane 5) 2)))))
        (if (and (in-bounds? sample)
                 (match (ground-at (World-land world) sample)
                   ((Rock) #t)
                   (_ #f)))
            (Raider)
            (Minion))))

    ;; About one enemy in ten burrows through rock.
    (: add-enemy (-> World Nest Behavior I64 I64 World))
    (define (add-enemy world nest behavior lane rank)
      (match (fresh-id world)
        ((Pair id world)
         (let* ((cell
                 (Cell (+ (Cell-x (Nest-cell nest)) (- (remainder lane 3) 1))
                       (+ (Cell-y (Nest-cell nest)) 2)))
                (health (spawn-health world behavior rank))
                (burrower (= (remainder (+ (remainder (World-seed world) 10)
                                           (remainder id 10))
                                        10)
                             0)))
           (World-enemies-set world (append (World-enemies world)
                                            (list (Enemy id
                                                         behavior
                                                         rank
                                                         burrower
                                                         cell
                                                         cell
                                                         health
                                                         health
                                                         (raid-target world
                                                                      nest
                                                                      behavior)
                                                         (None)))))))))

    ;; A raider picks the nearest exposed outpost on its own approach: a
    ;; finished extractor or pylon on the mainland, more than nine cells
    ;; from the hub and nearer this nest than the hub is. Without one it
    ;; attacks the hub.
    (: raid-target (-> World Nest Behavior (Option I64)))
    (define (raid-target world nest behavior)
      (match behavior
        ((Raider)
         (let* ((hub (Hub-cell (World-hub world)))
                (front (Nest-cell nest))
                (limit (manhattan front hub)))
           (match (nearest (filter (lambda (b)
                                     (and (exposed? b hub front limit)
                                          (mainland? (World-land world)
                                                     (Building-cell b))))
                                   (World-buildings world))
                           (lambda (b) (manhattan front (Building-cell b))))
             ((Some b) (Some (Building-id b)))
             ((None) (None)))))
        (_ (None))))

    (: exposed? (-> Building Cell Cell I64 Bool))
    (define (exposed? building hub front limit)
      (and (built? building)
           (match (Building-kind building) ((Turret) #f) (_ #t))
           (> (manhattan (Building-cell building) hub) 9)
           (< (manhattan front (Building-cell building)) limit)))

    ;; The first of the nearest, so ties go to the oldest.
    (: nearest (All (A) (-> (List A) (-> A I64) (Option A))))
    (define (nearest items distance)
      (fold-left (lambda (best item)
                   (match best
                     ((Some other)
                      (if (< (distance item) (distance other))
                          (Some item)
                          best))
                     ((None) (Some item))))
                 (None) items))

    ;; ---- Routes ----

    ;; Walkers cross open ground, ice and opened rock; burrowers also cross
    ;; intact rock, which they dig through. Nobody crosses water. Each route is a
    ;; distance field toward a goal, kept until the terrain changes.
    (: route-field (-> World Cell Bool (Pair (Vector I64) World)))
    (define (route-field world goal burrower)
      (match (find (lambda (route)
                     (and (cell=? (Route-goal route) goal)
                          (eq-bool? (Route-burrower route) burrower)))
                   (World-routes world))
        ((Some route) (Pair (Route-field route) world))
        ((None)
         (let ((field (distance-field (passable world burrower)
                                      (goal-cells world goal))))
           (Pair field
                 (World-routes-set world
                                   (take (Cons (Route goal burrower field)
                                               (World-routes world))
                                         8)))))))

    (: eq-bool? (-> Bool Bool Bool))
    (define (eq-bool? a b)
      (if a b (not b)))

    ;; The hub's goal is its whole footprint.
    (: goal-cells (-> World Cell (List Cell)))
    (define (goal-cells world goal)
      (let ((hub (World-hub world)))
        (if (cell=? goal (Hub-cell hub))
            (filter (lambda (cell) (hub-cell? hub cell))
                    (map (lambda (i)
                           (Cell (+ (Cell-x goal) (- (remainder i 3) 1))
                                 (+ (Cell-y goal) (- (quotient i 3) 1))))
                         (iota 9)))
            (list goal))))

    (: passable (-> World Bool (Vector Bool)))
    (define (passable world burrower)
      (vector-generate (* map-size map-size)
                       (lambda (index)
                         (let ((cell (index-cell index)))
                           (match (ground-at (World-land world) cell)
                             ((Rock) (or burrower (opened? world cell)))
                             ((Water) #f)
                             (_ #t))))))


    ;; ---- Movement ----

    (: target-cell (-> World Enemy Cell))
    (define (target-cell world enemy)
      (match (target-building world enemy)
        ((Some b) (Building-cell b))
        ((None) (Hub-cell (World-hub world)))))

    ;; The turret an enemy turned on while it stands, else the outpost it
    ;; raids while that stands; with neither it heads for the hub.
    (: target-building (-> World Enemy (Option Building)))
    (define (target-building world enemy)
      (match (standing world (Enemy-aggro enemy))
        ((Some b) (Some b))
        ((None) (standing world (Enemy-raid enemy)))))

    (: standing (-> World (Option I64) (Option Building)))
    (define (standing world id)
      (match id
        ((Some id)
         (match (building world id)
           ((Some b) (if (built? b) (Some b) (None)))
           ((None) (None))))
        ((None) (None))))

    ;; What an engaged enemy strikes.
    (enum Struck
      (StruckHub)
      (StruckBuilding ((building Building))))

    ;; An enemy stops beside its target and strikes it. One heading for the
    ;; hub stops beside the hub, or beside any finished building it meets.
    (: engagement (-> World Enemy (Option Struck)))
    (define (engagement world enemy)
      (let ((cell (Enemy-cell enemy)))
        (match (target-building world enemy)
          ((Some b)
           (if (beside? cell (Building-cell b))
               (Some (StruckBuilding b))
               (None)))
          ((None) (cond ((beside-hub? world cell) (Some (StruckHub)))
                        (else (match (beside-buildings world cell)
                                ((Cons b _) (Some (StruckBuilding b)))
                                ((Nil) (None)))))))))

    (: engaged? (-> World Enemy Bool))
    (define (engaged? world enemy)
      (match (engagement world enemy)
        ((Some _) #t)
        ((None) #f)))

    (: beside? (-> Cell Cell Bool))
    (define (beside? a b)
      (<= (distance-squared a b) 1))

    (: beside-hub? (-> World Cell Bool))
    (define (beside-hub? world cell)
      (any? (lambda (neighbor) (hub-cell? (World-hub world) neighbor))
            (Cons cell (neighbors cell))))

    (: beside-buildings (-> World Cell (List Building)))
    (define (beside-buildings world cell)
      (filter (lambda (b) (and (built? b) (beside? cell (Building-cell b))))
              (World-buildings world)))

    ;; The neighbor one step closer to the goal with the fewest enemies on
    ;; it, so crowds spread across parallel lanes.
    (: next-cell (-> World (Vector I64) (Vector I64) Cell (Option Cell)))
    (define (next-cell world field crowd cell)
      (let ((here (vector-ref field (cell-index cell))))
        (nearest (filter (lambda (n)
                           (and (> here 0)
                                (= (vector-ref field (cell-index n))
                                   (- here 1))))
                         (neighbors cell))
                 (lambda (n) (vector-ref crowd (cell-index n))))))

    (: crowding (-> World (Vector I64)))
    (define (crowding world)
      (unsafe-total
       (lambda ()
         (let ((counts (make-array (* map-size map-size) 0)))
           (for-each (lambda (e)
                       (array-set! counts
                                   (cell-index (Enemy-cell e))
                                   (+ 1
                                      (array-ref counts
                                                 (cell-index (Enemy-cell e))))))
                     (World-enemies world))
           (array->vector counts)))))

    ;; On its period an enemy that is not engaged steps toward its target,
    ;; unless the step is into rock still being dug.
    (: march (-> World World))
    (define (march world)
      (let ((crowd (crowding world)))
        (fold-left (lambda (world enemy)
                     (if (on-step? world enemy) (step world crowd enemy) world))
                   world
                   (World-enemies world))))

    (: step (-> World (Vector I64) Enemy World))
    (define (step world crowd enemy)
      (let ((enemy (Enemy-previous-set enemy (Enemy-cell enemy))))
        (match (heading world crowd enemy)
          ((Pair (Some cell) world)
           (put-enemy world
                      (if (walkable? world cell)
                          (Enemy-cell-set enemy cell)
                          enemy)))
          ((Pair (None) world) (put-enemy world enemy)))))

    ;; The next cell toward the enemy's target, if it is not engaged, with
    ;; the world holding the route it used.
    (: heading (-> World (Vector I64) Enemy (Pair (Option Cell) World)))
    (define (heading world crowd enemy)
      (if (engaged? world enemy)
          (Pair (None) world)
          (match (route-field world
                              (target-cell world enemy)
                              (Enemy-burrower enemy))
            ((Pair field world)
             (Pair (next-cell world field crowd (Enemy-cell enemy)) world)))))

    (: walkable? (-> World Cell Bool))
    (define (walkable? world cell)
      (match (ground-at (World-land world) cell)
        ((Rock) (opened? world cell))
        ((Water) #f)
        (_ #t)))

    (: on-step? (-> World Enemy Bool))
    (define (on-step? world enemy)
      (= (remainder (+ (World-tick world) (Enemy-id enemy))
                    (enemy-period (Enemy-behavior enemy)))
         0))

    (: put-enemy (-> World Enemy World))
    (define (put-enemy world enemy)
      (World-enemies-set world
                         (map (lambda (e)
                                (if (= (Enemy-id e) (Enemy-id enemy)) enemy e))
                              (World-enemies world))))

    ;; ---- Excavation ----

    ;; A burrower facing intact rock chips it, one point a tick, with at most
    ;; two working on a cell: even a crowd needs four seconds to open one.
    (: excavate (-> World World))
    (define (excavate world)
      (match (dig-faces world)
        ((Pair faces world)
         (fold-left (lambda (world cell)
                      (chip world
                            cell
                            (min 2
                                 (length (filter (lambda (c) (cell=? c cell))
                                                 faces)))))
                    world (delete-duplicates cell=? faces)))))

    ;; The rock each burrower is about to dig into.
    (: dig-faces (-> World (Pair (List Cell) World)))
    (define (dig-faces world)
      (let ((crowd (crowding world)))
        (fold-left (lambda (found enemy)
                     (match (heading (Pair-second found) crowd enemy)
                       ((Pair (Some cell) world)
                        (Pair (if (walkable? world cell)
                                  (Pair-first found)
                                  (Cons cell (Pair-first found)))
                              world))
                       ((Pair (None) world) (Pair (Pair-first found) world))))
                   (Pair (Nil) world)
                   (filter Enemy-burrower (World-enemies world)))))

    (: chip (-> World Cell I64 World))
    (define (chip world cell amount)
      (let ((remaining (- (match (find (lambda (d) (cell=? (Dig-cell d) cell))
                                       (World-digs world))
                            ((Some d) (Dig-remaining d))
                            ((None) rock-health))
                          amount))
            (others (filter (lambda (d) (not (cell=? (Dig-cell d) cell)))
                            (World-digs world))))
        (if (<= remaining 0)
            (open-rock (World-digs-set world others) cell)
            (World-digs-set world (Cons (Dig cell remaining) others)))))

    ;; ---- Turrets ----

    ;; A powered turret fires every eight ticks at the nearest visible enemy
    ;; in range and in line of sight, so it deals first with what is doing
    ;; damage close by; without one it fires at a nest in range. The enemy
    ;; it hits may turn on it.
    (: fire (-> World World))
    (define (fire world)
      (fold-left fire-one
                 world
                 (filter (lambda (b)
                           (and (turret? b)
                                (built? b)
                                (powered? world (Building-id b))
                                (= (remainder
                                    (+ (World-tick world) (Building-id b))
                                    8)
                                   0)))
                         (World-buildings world))))

    (: turret? (-> Building Bool))
    (define (turret? b)
      (match (Building-kind b) ((Turret) #t) (_ #f)))

    (: fire-one (-> World Building World))
    (define (fire-one world turret)
      (match (choose-enemy world turret)
        ((Some enemy) (hit-enemy world turret enemy))
        ((None)
         (match (find (lambda (nest) (can-shoot? world turret (Nest-cell nest)))
                      (living-nests world))
           ((Some nest) (hit-nest world turret nest))
           ((None) world)))))

    (: can-shoot? (-> World Building Cell Bool))
    (define (can-shoot? world turret cell)
      (and (visible? world cell)
           (within? cell (Building-cell turret) 6)
           (clear-line? world (Building-cell turret) cell)))

    ;; The nearest enemy the turret can shoot; ties go to the oldest.
    (: choose-enemy (-> World Building (Option Enemy)))
    (define (choose-enemy world turret)
      (nearest (filter (lambda (e) (can-shoot? world turret (Enemy-cell e)))
                       (World-enemies world))
               (lambda (e)
                 (distance-squared (Enemy-cell e) (Building-cell turret)))))

    ;; Damage falls from 24 at point blank to 6 at the six-cell range,
    ;; measured in fortieths of a cell, and grows with the turret's level:
    ;; one, one and a half, then two times.
    (: damage (-> Building Cell I64))
    (define (damage turret cell)
      (let ((length (integer-sqrt
                     (* 1600 (distance-squared cell (Building-cell turret))))))
        (quotient (* (+ 6 (quotient (* 18 (- 240 length)) 240))
                     (+ (Building-level turret) 1))
                  2)))

    (: hit-enemy (-> World Building Enemy World))
    (define (hit-enemy world turret enemy)
      (let ((wounded (Enemy-health-set enemy
                                       (- (Enemy-health enemy)
                                          (damage turret (Enemy-cell enemy))))))
        (shoot (put-enemy world
                          (if (> (Enemy-health wounded) 0)
                              (provoke world wounded turret)
                              wounded))
               turret (Enemy-cell enemy))))

    ;; A wounded enemy turns on the turret that hit it unless the one it
    ;; already turned on still stands, so turrets on both sides of it cannot
    ;; pull it back and forth. A turret across water is out of its reach,
    ;; and it keeps on its way.
    (: provoke (-> World Enemy Building Enemy))
    (define (provoke world enemy turret)
      (match (standing world (Enemy-aggro enemy))
        ((Some _) enemy)
        ((None)
         (if (mainland? (World-land world) (Building-cell turret))
             (Enemy-aggro-set enemy (Some (Building-id turret)))
             enemy))))

    ;; A destroyed nest changes the structures: its crystal shows instead.
    (: hit-nest (-> World Building Nest World))
    (define (hit-nest world turret nest)
      (let* ((health
              (max 0 (- (Nest-health nest) (damage turret (Nest-cell nest)))))
             (world (World-nests-set world
                                     (map (lambda (n)
                                            (if (= (Nest-front n)
                                                   (Nest-front nest))
                                                (Nest-health-set n health)
                                                n))
                                          (World-nests world)))))
        (shoot (if (= health 0) (structures-changed world) world)
               turret
               (Nest-cell nest))))

    ;; A shot leaves a tracer and turns the turret's guns to where it went.
    (: shoot (-> World Building Cell World))
    (define (shoot world turret cell)
      (World-buildings-set (World-shots-set world
                                            (Cons (Shot (Building-cell turret)
                                                        cell
                                                        (World-tick world))
                                                  (World-shots world)))
                           (map (lambda (b)
                                  (if (= (Building-id b) (Building-id turret))
                                      (Building-aim-set b (Some cell))
                                      b))
                                (World-buildings world))))

    ;; ---- Strikes ----

    ;; Every ten ticks each engaged enemy strikes for its rank's damage.
    (: strike (-> World World))
    (define (strike world)
      (if (= (remainder (World-tick world) 10) 0)
          (fold-left strike-one world (World-enemies world))
          world))

    (: strike-one (-> World Enemy World))
    (define (strike-one world enemy)
      (match (engagement world enemy)
        ((Some (StruckHub)) (damage-hub world (rank-damage (Enemy-rank enemy))))
        ((Some (StruckBuilding b))
         (damage-building world b (rank-damage (Enemy-rank enemy))))
        ((None) world)))

    (: damage-building (-> World Building I64 World))
    (define (damage-building world b amount)
      (alert (put-building world
                           (Building-health-set b
                                                (max 0
                                                     (- (Building-health b)
                                                        amount))))
             (Building-cell b)))

    (: damage-hub (-> World I64 World))
    (define (damage-hub world amount)
      (let ((hub (World-hub world)))
        (alert (World-hub-set world
                              (Hub-health-set hub
                                              (max 0
                                                   (- (Hub-health hub)
                                                      amount))))
               (Hub-cell hub))))

    ;; At most four alerts: a new one replaces any within four cells and any
    ;; older than eight seconds.
    (: alert (-> World Cell World))
    (define (alert world cell)
      (let ((tick (World-tick world)))
        (World-alerts-set world (Cons (Alert cell tick)
                                      (take (filter (lambda (a)
                                                      (and (<= (- tick
                                                                  (Alert-tick
                                                                   a))
                                                               80)
                                                           (not (within?
                                                                 (Alert-cell a)
                                                                 cell
                                                                 4))))
                                                    (World-alerts world))
                                            3)))))

    ;; ---- Settling ----

    ;; Removes the dead and destroyed, counts them, and drops old shots.
    (: settle (-> World World))
    (define (settle world)
      (let* ((alive (filter (lambda (e) (> (Enemy-health e) 0))
                            (World-enemies world)))
             (standing (filter (lambda (b) (> (Building-health b) 0))
                               (World-buildings world)))
             (world (count-losses world
                                  (- (length (World-enemies world))
                                     (length alive))
                                  (- (length (World-buildings world))
                                     (length standing))))
             (world (World-shots-set (World-enemies-set world alive)
                                     (filter (lambda (s)
                                               (> (+ (Shot-tick s) 4)
                                                  (World-tick world)))
                                             (World-shots world)))))
        (if (= (length standing) (length (World-buildings world)))
            world
            (rewire (World-buildings-set world standing)))))

    (: count-losses (-> World I64 I64 World))
    (define (count-losses world kills lost)
      (let ((ledger (World-ledger world)))
        (World-ledger-set world
                          (Ledger-lost-set (Ledger-kills-set ledger
                                                             (+ (Ledger-kills
                                                                 ledger)
                                                                kills))
                                           (+ (Ledger-lost ledger) lost)))))

    ;; Destroying every nest wins, even on the tick the hub falls. Either way
    ;; the whole map is uncovered for inspection.
    (: judge (-> World World))
    (define (judge world)
      (cond
       ((null? (living-nests world)) (uncover (World-outcome-set world (Won))))
       ((= (Hub-health (World-hub world)) 0)
        (uncover (World-outcome-set world (Lost))))
       (else world)))

    ))
