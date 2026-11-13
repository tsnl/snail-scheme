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
    (define (wave-interval) (→ I64) 300)

    (define (first-wave) (→ I64) 450)

    (define (difficulty-step) (→ I64) 900)

    (define (first-raid) (→ I64) 1050)

    (define (raid-interval) (→ I64) 600)

    (define (boss-interval) (→ I64) 5400)

    (define (maximum-enemies) (→ I64) 128)

    (enum AttackKind
      (Regular)
      (Raid)
      (Heavy))

    (define (heavy? (tick I64)) (→ Bool)
      (and (>= tick (boss-interval)) (= (remainder tick (boss-interval)) 0)))

    (define (raid? (tick I64)) (→ Bool)
      (and (>= tick (first-raid)) (= (remainder (- tick (first-raid)) (raid-interval)) 0)))

    (define (regular? (tick I64)) (→ Bool)
      (and (>= tick (first-wave)) (= (remainder (- tick (first-wave)) (wave-interval)) 0)))

    (define (attack-kind (tick I64)) (→ AttackKind)
      (cond ((heavy? tick) (Heavy))
            ((raid? tick) (Raid))
            (else (Regular))))

    ;; How many enemies attack at `tick`; zero when no attack is due. Sizes
    ;; grow more slowly than strength.
    (define (attack-size (tick I64)) (→ I64)
      (cond ((heavy? tick) (+ 12 (min 14 (quotient (- tick (boss-interval)) (boss-interval)))))
            ((raid? tick) (+ 11 (min 15 (quotient (- tick (first-raid)) (raid-interval)))))
            ((regular? tick)
             (+ 8 (min 18 (quotient (- tick (first-wave)) (* 3 (difficulty-step))))))
            (else 0)))

    (define (next-attack-tick (tick I64)) (→ I64)
      (let loop ((candidate
                  (* (quotient (wave-interval) 2)
                     (+ 1 (quotient tick (quotient (wave-interval) 2))))))
        (if (> (attack-size candidate) 0)
            candidate
            (loop (+ candidate (quotient (wave-interval) 2))))))

    ;; Attacks numbered from one; raids take regular slots and bosses fall
    ;; between them.
    (define (attack-number (tick I64)) (→ I64)
      (+ 1
         (+ (if (< tick (first-wave)) 0 (+ 1 (quotient (- tick (first-wave)) (wave-interval))))
            (quotient tick (boss-interval)))))

    ;; ---- Strength ----

    ;; Strength rises a tier every ninety seconds, up to forty. Each cleared
    ;; nest takes back two tiers, after capping, so even a late clear helps.
    (define (threat-tick (world World)) (→ I64)
      (max 0
           (- (min (● world tick) (* 40 (difficulty-step)))
              (* (* 2 (difficulty-step)) (- 3 (length (living-nests world)))))))

    (define (difficulty-tier (tick I64)) (→ I64)
      (min 40 (quotient tick (difficulty-step))))

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
      (filter (lambda (nest) (> (● nest health) 0)) (● world nests)))

    ;; Each attack deals its enemies to the fronts in turn, starting where
    ;; the last one left off. A cleared front's share is skipped, never given
    ;; to the others.
    (define (spawn (world World)) (→ World)
      (let* ((tick (● world tick)) (size (attack-size tick)) (kind (attack-kind tick))
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
        (match (find (lambda (nest) (= (● nest front) (remainder (+ index shift) 3)))
                     (● world nests))
          ((Some nest)
           (if (or (= (● nest health) 0) (>= (length (● world enemies)) (maximum-enemies)))
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
      (let ((sample (Cell (+ (● (● nest cell) x) (if (= (remainder lane 3) 0) -12 12))
                          (+ (● (● nest cell) y) (- (remainder lane 5) 2)))))
        (if
         (and (in-bounds? sample) (match (ground-at (● world land) sample) ((Rock) #t) (_ #f)))
         (Raider)
         (Minion))))

    ;; About one enemy in ten burrows through rock.
    (define (add-enemy (world World) (nest Nest) (behavior Behavior) (lane I64) (rank I64))
      (→ World)
      (match (fresh-id world)
        ((Pair id world)
         (let* ((cell (Cell (+ (● (● nest cell) x) (- (remainder lane 3) 1))
                            (+ (● (● nest cell) y) 2)))
                (health (spawn-health world behavior rank))
                (burrower
                 (= (remainder (+ (remainder (● world seed) 10) (remainder id 10)) 10) 0)))
           (World-enemies-set world (append (● world enemies)
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
         (let* ((hub (● (● world hub) cell))
                (front (● nest cell))
                (limit (manhattan front hub)))
           (match (nearest (filter (lambda (b)
                                     (and (exposed? b hub front limit)
                                          (mainland? (● world land) (● b cell))))
                                   (● world buildings))
                           (lambda (b) (manhattan front (● b cell))))
             ((Some b) (Some (● b id)))
             ((None) (None)))))
        (_ (None))))

    (define (exposed? (building Building) (hub Cell) (front Cell) (limit I64)) (→ Bool)
      (and (built? building) (match (● building kind) ((Turret) #f) (_ #t))
           (> (manhattan (● building cell) hub) 9)
           (< (manhattan front (● building cell)) limit)))

    ;; The first of the nearest, so ties go to the oldest.
    (define (nearest (items (List A)) (distance (Fn A → I64)))
      (→ (Option A))
      (∀ (A))
      (⊨ (Copy A) (Drop (!) A))
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
                     (and (cell=? (● route goal) goal)
                          (eq-bool? (● route burrower) burrower)))
                   (● world routes))
        ((Some route) (Pair (● route field) world))
        ((None) (let ((field (distance-field (passable world burrower) (goal-cells world goal))))
                  (Pair field
                        (World-routes-set world
                                          (take
                                           (Cons (Route goal burrower field) (● world routes))
                                           8)))))))

    (define (eq-bool? (a Bool) (b Bool)) (→ Bool)
      (if a b (not b)))

    ;; The hub's goal is its whole footprint.
    (define (goal-cells (world World) (goal Cell)) (→ (List Cell))
      (let ((hub (● world hub)))
        (if (cell=? goal (● hub cell))
            (filter (lambda (cell) (hub-cell? hub cell))
                    (map (lambda (i)
                           (Cell (+ (● goal x) (- (remainder i 3) 1))
                                 (+ (● goal y) (- (quotient i 3) 1))))
                         (iota 9)))
            (list goal))))

    (define (passable (world World) (burrower Bool)) (→ (Vector Bool))
      (vector-generate (* (map-size) (map-size))
                       (lambda (index)
                         (let ((cell (index-cell index)))
                           (match (ground-at (● world land) cell)
                             ((Rock) (or burrower (opened? world cell)))
                             ((Water) #f)
                             (_ #t))))))

    ;; ---- Movement ----

    (define (target-cell (world World) (enemy Enemy)) (→ Cell)
      (match (target-building world enemy)
        ((Some b) (● b cell))
        ((None) (● (● world hub) cell))))

    ;; The turret an enemy turned on while it stands, else the outpost it
    ;; raids while that stands; with neither it heads for the hub.
    (define (target-building (world World) (enemy Enemy)) (→ (Option Building))
      (match (standing world (● enemy aggro))
        ((Some b) (Some b))
        ((None) (standing world (● enemy raid)))))

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
      (let ((cell (● enemy cell)))
        (match (target-building world enemy)
          ((Some b) (if (beside? cell (● b cell)) (Some (StruckBuilding b)) (None)))
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
      (any? (lambda (neighbor) (hub-cell? (● world hub) neighbor))
            (Cons cell (neighbors cell))))

    (define (beside-buildings (world World) (cell Cell)) (→ (List Building))
      (filter (lambda (b) (and (built? b) (beside? cell (● b cell))))
              (● world buildings)))

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
         (let ((counts (make-vector (* (map-size) (map-size)) 0)))
           (for-each (lambda (e)
                       (vector-set! counts
                                    (cell-index (● e cell))
                                    (+ 1 (vector-ref counts (cell-index (● e cell))))))
                     (● world enemies))
           counts))))

    ;; On its period an enemy that is not engaged steps toward its target,
    ;; unless the step is into rock still being dug.
    (define (march (world World)) (→ World)
      (let ((crowd (crowding world)))
        (fold-left (lambda (world enemy) (if (on-step? world enemy) (step world crowd enemy) world))
                   world
                   (● world enemies))))

    (define (step (world World) (crowd (Vector I64)) (enemy Enemy)) (→ World)
      (let ((enemy (Enemy-previous-set enemy (● enemy cell))))
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
          (match (route-field world (target-cell world enemy) (● enemy burrower))
            ((Pair field world) (Pair (next-cell world field crowd (● enemy cell)) world)))))

    (define (walkable? (world World) (cell Cell)) (→ Bool)
      (match (ground-at (● world land) cell)
        ((Rock) (opened? world cell))
        ((Water) #f)
        (_ #t)))

    (define (on-step? (world World) (enemy Enemy)) (→ Bool)
      (= (remainder (+ (● world tick) (● enemy id)) (enemy-period (● enemy behavior)))
         0))

    (define (put-enemy (world World) (enemy Enemy)) (→ World)
      (World-enemies-set world
                         (map (lambda (e) (if (= (● e id) (● enemy id)) enemy e))
                              (● world enemies))))

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
                     (match (heading (● found second) crowd enemy)
                       ((Pair (Some cell) world)
                        (Pair (if (walkable? world cell)
                                  (● found first)
                                  (Cons cell (● found first)))
                              world))
                       ((Pair (None) world) (Pair (● found first) world))))
                   (Pair (Nil) world)
                   (filter (lambda (record) (● record burrower)) (● world enemies)))))

    (define (chip (world World) (cell Cell) (amount I64)) (→ World)
      (let ((remaining (- (match (find (lambda (d) (cell=? (● d cell) cell)) (● world digs))
                            ((Some d) (● d remaining))
                            ((None) (rock-health)))
                          amount))
            (others (filter (lambda (d) (not (cell=? (● d cell) cell))) (● world digs))))
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
                 (filter (lambda (b) (and (turret? b) (built? b) (powered? world (● b id))
                                          (= (remainder (+ (● world tick) (● b id)) 8)
                                             0)))
                         (● world buildings))))

    (define (turret? (b Building)) (→ Bool)
      (match (● b kind) ((Turret) #t) (_ #f)))

    (define (fire-one (world World) (turret Building)) (→ World)
      (match (choose-enemy world turret)
        ((Some enemy) (hit-enemy world turret enemy))
        ((None)
         (match (find (lambda (nest) (can-shoot? world turret (● nest cell)))
                      (living-nests world))
           ((Some nest) (hit-nest world turret nest))
           ((None) world)))))

    (define (can-shoot? (world World) (turret Building) (cell Cell)) (→ Bool)
      (and (visible? world cell)
           (within? cell (● turret cell) 6)
           (clear-line? world (● turret cell) cell)))

    ;; The nearest enemy the turret can shoot; ties go to the oldest.
    (define (choose-enemy (world World) (turret Building)) (→ (Option Enemy))
      (nearest (filter (lambda (e) (can-shoot? world turret (● e cell))) (● world enemies))
               (lambda (e) (distance-squared (● e cell) (● turret cell)))))

    ;; Damage falls from 24 at point blank to 6 at the six-cell range,
    ;; measured in fortieths of a cell, and grows with the turret's level:
    ;; one, one and a half, then two times.
    (define (damage (turret Building) (cell Cell)) (→ I64)
      (let ((length (integer-sqrt (* 1600 (distance-squared cell (● turret cell))))))
        (quotient (* (+ 6 (quotient (* 18 (- 240 length)) 240)) (+ (● turret level) 1)) 2)))

    (define (hit-enemy (world World) (turret Building) (enemy Enemy)) (→ World)
      (let ((wounded
             (Enemy-health-set enemy (- (● enemy health) (damage turret (● enemy cell))))))
        (shoot
         (put-enemy world (if (> (● wounded health) 0) (provoke world wounded turret) wounded))
         turret (● enemy cell))))

    ;; A wounded enemy turns on the turret that hit it unless the one it
    ;; already turned on still stands, so turrets on both sides of it cannot
    ;; pull it back and forth. A turret across water is out of its reach,
    ;; and it keeps on its way.
    (define (provoke (world World) (enemy Enemy) (turret Building)) (→ Enemy)
      (match (standing world (● enemy aggro))
        ((Some _) enemy)
        ((None)
         (if (mainland? (● world land) (● turret cell))
             (Enemy-aggro-set enemy (Some (● turret id)))
             enemy))))

    ;; A destroyed nest changes the structures: its crystal shows instead.
    (define (hit-nest (world World) (turret Building) (nest Nest)) (→ World)
      (let* ((health (max 0 (- (● nest health) (damage turret (● nest cell)))))
             (world (World-nests-set world
                                     (map (lambda (n)
                                            (if (= (● n front) (● nest front))
                                                (Nest-health-set n health)
                                                n))
                                          (● world nests)))))
        (shoot (if (= health 0) (structures-changed world) world) turret (● nest cell))))

    ;; A shot leaves a tracer and turns the turret's guns to where it went.
    (define (shoot (world World) (turret Building) (cell Cell)) (→ World)
      (World-buildings-set (World-shots-set world
                                            (Cons
                                             (Shot (● turret cell) cell (● world tick))
                                             (● world shots)))
                           (map (lambda (b)
                                  (if (= (● b id) (● turret id))
                                      (Building-aim-set b (Some cell))
                                      b))
                                (● world buildings))))

    ;; ---- Strikes ----

    ;; Every ten ticks each engaged enemy strikes for its rank's damage.
    (define (strike (world World)) (→ World)
      (if (= (remainder (● world tick) 10) 0)
          (fold-left strike-one world (● world enemies))
          world))

    (define (strike-one (world World) (enemy Enemy)) (→ World)
      (match (engagement world enemy)
        ((Some (StruckHub)) (damage-hub world (rank-damage (● enemy rank))))
        ((Some (StruckBuilding b)) (damage-building world b (rank-damage (● enemy rank))))
        ((None) world)))

    (define (damage-building (world World) (b Building) (amount I64)) (→ World)
      (alert (put-building world (Building-health-set b (max 0 (- (● b health) amount))))
             (● b cell)))

    (define (damage-hub (world World) (amount I64)) (→ World)
      (let ((hub (● world hub)))
        (alert (World-hub-set world (Hub-health-set hub (max 0 (- (● hub health) amount))))
               (● hub cell))))

    ;; At most four alerts: a new one replaces any within four cells and any
    ;; older than eight seconds.
    (define (alert (world World) (cell Cell)) (→ World)
      (let ((tick (● world tick)))
        (World-alerts-set world (Cons (Alert cell tick)
                                      (take (filter (lambda (a)
                                                      (and (<= (- tick (● a tick)) 80)
                                                           (not (within? (● a cell) cell 4))))
                                                    (● world alerts))
                                            3)))))

    ;; ---- Settling ----

    ;; Removes the dead and destroyed, counts them, and drops old shots.
    (define (settle (world World)) (→ World)
      (let* ((alive (filter (lambda (e) (> (● e health) 0)) (● world enemies)))
             (standing (filter (lambda (b) (> (● b health) 0)) (● world buildings)))
             (world (count-losses world
                                  (- (length (● world enemies)) (length alive))
                                  (- (length (● world buildings)) (length standing))))
             (world (World-shots-set (World-enemies-set world alive)
                                     (filter (lambda (s) (> (+ (● s tick) 4) (● world tick)))
                                             (● world shots)))))
        (if (= (length standing) (length (● world buildings)))
            world
            (rewire (World-buildings-set world standing)))))

    (define (count-losses (world World) (kills I64) (lost I64)) (→ World)
      (let ((ledger (● world ledger)))
        (World-ledger-set world
                          (Ledger-lost-set (Ledger-kills-set ledger (+ (● ledger kills) kills))
                                           (+ (● ledger lost) lost)))))

    ;; Destroying every nest wins, even on the tick the hub falls. Either way
    ;; the whole map is uncovered for inspection.
    (define (judge (world World)) (→ World)
      (cond ((null? (living-nests world)) (uncover (World-outcome-set world (Won))))
            ((= (● (● world hub) health) 0) (uncover (World-outcome-set world (Lost))))
            (else world)))

    ))
