;; The nests' side of the game, as in the original Siegework: escalating
;; waves from three fronts, raids and a boss, enemies that make for the
;; hub and attack what they meet on the way, turrets that shoot back, and
;; the outcome.
;;
;; An enemy knows the whole terrain, walls included, and where the hub is,
;; but sees structures and workers only within four cells, through rock
;; and walls alike. It heads for the hub on a nearly shortest route, digging
;; through rock and walls when it chooses to; something that comes into
;; sight may provoke it, and then it attacks whatever is nearest until
;; nothing is left in sight. Every chance it takes is drawn from the seed,
;; its id and the tick, so a journal of orders replays it exactly.
;;
;; Time is the world's tick. Waves, strength tiers and raids follow fixed
;; schedules; enemies step on multiples of their period, dig every other
;; tick and strike every ten ticks; turrets fire every eight. No unit keeps
;; a countdown.
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
   (lofi base)
   (siegework grid)
   (siegework terrain)
   (siegework world)
   (siegework routes))
  (begin

    ;; A ten-minute expedition gets forty-five seconds before waves every
    ;; sixty seconds. Strength rises every ninety seconds; raids replace
    ;; every other wave from 1:45, and bosses come every nine minutes.
    ;; Every attack falls on a multiple of fifteen seconds.
    (: wave-interval I64)
    (define wave-interval 600)

    (: first-wave I64)
    (define first-wave 450)

    (: difficulty-step I64)
    (define difficulty-step 900)

    (: first-raid I64)
    (define first-raid 1050)

    (: raid-interval I64)
    (define raid-interval 1200)

    (: boss-interval I64)
    (define boss-interval 5400)

    (: attack-step I64)
    (define attack-step 150)

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
      (and (>= tick first-raid) (= (remainder (- tick first-raid) raid-interval) 0)))

    (: regular? (-> I64 Bool))
    (define (regular? tick)
      (and (>= tick first-wave) (= (remainder (- tick first-wave) wave-interval) 0)))

    (: attack-kind (-> I64 AttackKind))
    (define (attack-kind tick)
      (cond ((heavy? tick) (Heavy))
            ((raid? tick) (Raid))
            (else (Regular))))

    ;; How many enemies attack at `tick`; zero when no attack is due. Sizes
    ;; grow more slowly than strength.
    (: attack-size (-> I64 I64))
    (define (attack-size tick)
      (cond ((heavy? tick) (+ 12 (min 14 (quotient (- tick boss-interval) boss-interval))))
            ((raid? tick) (+ 11 (min 15 (quotient (- tick first-raid) raid-interval))))
            ((regular? tick) (+ 8 (min 18 (quotient (- tick first-wave) (* 3 difficulty-step)))))
            (else 0)))

    (: next-attack-tick (-> I64 I64))
    (define (next-attack-tick tick)
      (let loop ((candidate (* attack-step (+ 1 (quotient tick attack-step)))))
        (if (> (attack-size candidate) 0) candidate (loop (+ candidate attack-step)))))

    ;; Attacks numbered from one; raids take regular slots and bosses fall
    ;; between them.
    (: attack-number (-> I64 I64))
    (define (attack-number tick)
      (+ 1 (+ (if (< tick first-wave) 0 (+ 1 (quotient (- tick first-wave) wave-interval))) (quotient tick boss-interval))))

    ;; ---- Strength ----

    ;; Strength rises a tier every ninety seconds, up to forty. Each cleared
    ;; nest takes back two tiers, after capping, so even a late clear helps.
    (: threat-tick (-> World I64))
    (define (threat-tick world)
      (max 0 (- (min (World-tick world) (* 40 difficulty-step)) (* (* 2 difficulty-step) (- 3 (length (living-nests world)))))))

    (: difficulty-tier (-> I64 I64))
    (define (difficulty-tier tick)
      (min 40 (quotient tick difficulty-step)))

    (: rank-health (-> I64 I64))
    (define (rank-health rank)
      (case rank ((0) 65) ((1) 90) ((2) 125) ((3) 180) ((4) 300) ((5) 500) (else 1800)))

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
      (let ((health (+ (rank-health rank) (* 15 (max 0 (- (difficulty-tier (threat-tick world)) 6))))))
        (match behavior
          ((Raider) (quotient (* 4 health) 5))
          (_ health))))

    (: enemy-period (-> Behavior I64))
    (define (enemy-period behavior)
      (match behavior
        ((Raider) 6)
        (_ 8)))

    ;; The damage an enemy digs for each hit: its rank's, three times that
    ;; for a burrower.
    (: dig-damage (-> Enemy I64))
    (define (dig-damage enemy)
      (* (rank-damage (Enemy-rank enemy)) (if (Enemy-burrower enemy) 3 1)))

    ;; ---- Chances ----

    ;; Each chance is named by a key, so no two draw the same numbers.
    (: burrow-key I64)
    (define burrow-key 101)

    (: aggression-key I64)
    (define aggression-key 102)

    (: provoke-key I64)
    (define provoke-key 103)

    (: dig-key I64)
    (define dig-key 104)

    (: sideways-key I64)
    (define sideways-key 105)

    (: lean-key I64)
    (define lean-key 106)

    ;; A number from 0 to 2^31 - 1 drawn from the world's seed, a key and
    ;; two numbers, such as an enemy's id and the tick.
    (: draw (-> World I64 I64 I64 I64))
    (define (draw world key a b)
      (hash (World-seed world) key a b))

    ;; A percent from 0 to 99, likewise.
    (: percent (-> World I64 I64 I64 I64))
    (define (percent world key a b)
      (remainder (draw world key a b) 100))

    ;; ---- Spawning ----

    (: living-nests (-> World (List Nest)))
    (define (living-nests world)
      (filter (lambda (nest) (> (Nest-health nest) 0)) (World-nests world)))

    ;; Each attack deals its enemies to the fronts in turn, starting where
    ;; the last one left off. A cleared front's share is skipped, never given
    ;; to the others.
    (: spawn (-> World World))
    (define (spawn world)
      (let* ((tick (World-tick world)) (size (attack-size tick)) (kind (attack-kind tick))
             (rank (min (match kind ((Heavy) 6) (_ 5)) (difficulty-tier (threat-tick world))))
             (shift (remainder (- (attack-number (- tick 1)) 1) 3)))
        (fold-left (lambda (world index) (spawn-one world kind size index rank shift)) world (iota size))))

    ;; Each enemy leaves its nest by one of three lanes.
    (: spawn-one (-> World AttackKind I64 I64 I64 I64 World))
    (define (spawn-one world kind size index rank shift)
      (let ((lane (+ 14 (* 2 (remainder (- size index) 3)))))
        (match (find (lambda (nest) (= (Nest-front nest) (remainder (+ index shift) 3))) (World-nests world))
          ((Some nest) (if (or (= (Nest-health nest) 0) (>= (length (World-enemies world)) maximum-enemies))
                           world
                           (add-enemy world nest (wave-behavior world nest kind index lane) lane (wave-rank rank index))))
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
      (let ((sample (Cell (+ (Cell-x (Nest-cell nest)) (if (= (remainder lane 3) 0) -12 12)) (+ (Cell-y (Nest-cell nest)) (- (remainder lane 5) 2)))))
        (if (and (in-bounds? sample) (match (ground-at (World-land world) sample) ((Rock) #t) (_ #f))) (Raider) (Minion))))

    ;; One enemy in twenty is a burrower. A new enemy has seen nothing yet
    ;; and has planned no route.
    (: add-enemy (-> World Nest Behavior I64 I64 World))
    (define (add-enemy world nest behavior lane rank)
      (match (fresh-id world)
        ((Pair id world)
         (let ((cell (Cell (+ (Cell-x (Nest-cell nest)) (- (remainder lane 3) 1)) (+ (Cell-y (Nest-cell nest)) 2)))
               (health (spawn-health world behavior rank)))
           (World-enemies-set world (append (World-enemies world)
                                            (list (Enemy id behavior rank (< (percent world burrow-key id 0) 5) (aggression world behavior id)
                                                         cell cell health health (Nil) (None) (Plan -1 -1 #f)))))))))

    ;; The percent chance an enemy attacks what comes into its sight: 10 to
    ;; 50 for a minion, 30 to 90 for a raider, 10 for a beast.
    (: aggression (-> World Behavior I64 I64))
    (define (aggression world behavior id)
      (match behavior
        ((Minion) (+ 10 (remainder (draw world aggression-key id 0) 41)))
        ((Raider) (+ 30 (remainder (draw world aggression-key id 0) 61)))
        ((Beast) 10)))

    ;; The first of the nearest, so ties go to the first listed.
    (: nearest (All (A) (-> (List A) (-> A I64) (Option A))))
    (define (nearest items distance)
      (fold-left (lambda (best item)
                   (match best
                     ((Some other) (if (< (distance item) (distance other)) (Some item) best))
                     ((None) (Some item))))
                 (None) items))

    ;; ---- Sight ----

    ;; What an enemy may attack: any building but a wall, which it treats as
    ;; terrain, or a worker.
    (enum Mark
      (MarkBuilding ((building Building)))
      (MarkWorker ((worker Worker))))

    (: mark-id (-> Mark I64))
    (define (mark-id mark)
      (match mark
        ((MarkBuilding b) (Building-id b))
        ((MarkWorker w) (Worker-id w))))

    (: mark-cell (-> Mark Cell))
    (define (mark-cell mark)
      (match mark
        ((MarkBuilding b) (Building-cell b))
        ((MarkWorker w) (Worker-cell w))))

    (: sight-radius I64)
    (define sight-radius 4)

    ;; The structures and workers within four cells that the enemy could
    ;; reach: those on the mainland, which water does not cut off from the
    ;; nests. Structures come first, each oldest first.
    (: in-sight (-> World Enemy (List Mark)))
    (define (in-sight world enemy)
      (let ((near? (lambda (cell) (and (within? cell (Enemy-cell enemy) sight-radius) (mainland? (World-land world) cell)))))
        (append (map (lambda (b) (MarkBuilding b)) (filter (lambda (b) (and (not (wall? b)) (near? (Building-cell b)))) (World-buildings world)))
                (map (lambda (w) (MarkWorker w)) (filter (lambda (w) (near? (Worker-cell w))) (World-workers world))))))

    ;; What an enemy's target names, while it stands.
    (: target-mark (-> World Enemy (Option Mark)))
    (define (target-mark world enemy)
      (match (Enemy-target enemy)
        ((Some id) (match (building world id)
                     ((Some b) (if (wall? b) (None) (Some (MarkBuilding b))))
                     ((None) (match (worker world id) ((Some w) (Some (MarkWorker w))) ((None) (None))))))
        ((None) (None))))

    ;; On each step an enemy rolls its aggression once for each thing newly
    ;; in sight. Once a roll says attack, it attacks the nearest thing in
    ;; sight, and goes on to the next nearest while anything is left there;
    ;; then it makes for the hub again. A turret that shoots it from beyond
    ;; its sight is not in sight, so it is not attacked.
    (: think (-> World Enemy Enemy))
    (define (think world enemy)
      (let* ((seen (in-sight world enemy))
             (fresh (filter (lambda (m) (not (member? (mark-id m) (Enemy-sighted enemy)))) seen))
             (provoked (any? (lambda (m) (< (percent world provoke-key (Enemy-id enemy) (mark-id m)) (Enemy-aggression enemy))) fresh))
             (attacking (or provoked (match (Enemy-target enemy) ((Some _) #t) ((None) #f)))))
        (Enemy-target-set (Enemy-sighted-set enemy (append (map mark-id fresh) (Enemy-sighted enemy)))
                          (if attacking
                              (match (nearest seen (lambda (m) (distance-squared (mark-cell m) (Enemy-cell enemy))))
                                ((Some m) (Some (mark-id m)))
                                ((None) (None)))
                              (None)))))

    ;; ---- Plans ----

    ;; The id an enemy's plan is for: its target, or 0 for the hub.
    (: goal-id (-> World Enemy I64))
    (define (goal-id world enemy)
      (match (target-mark world enemy)
        ((Some m) (mark-id m))
        ((None) 0)))

    ;; Where the enemy is going, as a single cell.
    (: goal-cell (-> World Enemy Cell))
    (define (goal-cell world enemy)
      (match (target-mark world enemy)
        ((Some m) (mark-cell m))
        ((None) (Hub-cell (World-hub world)))))

    (: mover (-> Enemy Bool Mover))
    (define (mover enemy digging)
      (Mover (enemy-period (Enemy-behavior enemy)) (if digging (dig-damage enemy) 0)))

    ;; The field toward the enemy's goal, digging or walking: over the whole
    ;; map toward the hub, kept with the world's routes, and over a window
    ;; around the enemy toward a target, which is always near.
    (: goal-field (-> World Enemy Bool (Pair Field World)))
    (define (goal-field world enemy digging)
      (match (target-mark world enemy)
        ((Some m) (Pair (window-field world (mover enemy digging) (Enemy-cell enemy) (mark-cell m)) world))
        ((None) (let ((hub (World-hub world))) (route-field world (Hub-cell hub) (hub-cells hub) (mover enemy digging))))))

    ;; An enemy plans its route when it takes a new goal or the terrain
    ;; changes, and chooses then whether to dig, weighing the best walking
    ;; route against the best route that may dig.
    (: plan (-> World Enemy (Pair Enemy World)))
    (define (plan world enemy)
      (let ((goal (goal-id world enemy)) (planned (Enemy-plan enemy)) (cell (Enemy-cell enemy)))
        (if (and (= (Plan-goal planned) goal) (= (Plan-terrain planned) (World-terrain world)))
            (Pair enemy world)
            (match (goal-field world enemy #f)
              ((Pair walk world)
               (match (goal-field world enemy #t)
                 ((Pair dig world)
                  (let ((chance (dig-chance enemy (field-cost walk cell) (field-cost dig cell))))
                    (Pair (Enemy-plan-set enemy (Plan goal (World-terrain world) (< (percent world dig-key (Enemy-id enemy) (World-tick world)) chance)))
                          world)))))))))

    ;; The percent chance of digging, from the ticks each route takes. Each
    ;; whole second the digging route saves adds x percent to a base chance:
    ;; 5 and 2 for most enemies, 15 and 4 for burrowers. With no walking
    ;; route the enemy digs.
    (: dig-chance (-> Enemy I64 I64 I64))
    (define (dig-chance enemy walk dig)
      (let ((base (if (Enemy-burrower enemy) 15 5)) (x (if (Enemy-burrower enemy) 4 2)) (saved (quotient (- walk dig) 10)))
        (cond ((< walk 0) 100)
              ((<= saved 0) base)
              (else (min 100 (+ base (* x saved)))))))

    ;; ---- Heading ----

    ;; An enemy's next cell on its planned route, which it steps or digs
    ;; into, with the enemy as planned and the world holding the routes it
    ;; used.
    (struct Bearing
      ((enemy Enemy)
       (world World)
       (next (Option Cell))))

    (: heading (-> World Enemy Bearing))
    (define (heading world enemy)
      (match (plan world enemy)
        ((Pair enemy world)
         (let ((digging (Plan-digging (Enemy-plan enemy))))
           (match (goal-field world enemy digging)
             ((Pair field world)
              (Bearing enemy world (choose-step world enemy (downhill field (lambda (cell) (enter-cost world (mover enemy digging) cell)) (Enemy-cell enemy))))))))))

    ;; Of the steps along a cheapest route, three in four go the way that
    ;; heads most directly at the goal, ties going to the enemy's lean, left
    ;; or right for its whole life; the fourth is any of them, so crowds
    ;; spread over routes no longer than the best.
    (: choose-step (-> World Enemy (List Cell) (Option Cell)))
    (define (choose-step world enemy steps)
      (let ((id (Enemy-id enemy)) (tick (World-tick world)))
        (cond ((null? steps) (None))
              ((< (percent world sideways-key id tick) 25) (Some (list-ref steps (remainder (draw world sideways-key tick id) (length steps)))))
              (else (nearest steps (lambda (step) (step-rank (goal-cell world enemy) (Enemy-cell enemy) step (lean world enemy))))))))

    (: lean (-> World Enemy I64))
    (define (lean world enemy)
      (if (= (remainder (draw world lean-key (Enemy-id enemy) 0) 2) 0) 1 -1))

    ;; Lower is better: the larger distance left along either axis, then
    ;; the turn toward the lean's side.
    (: step-rank (-> Cell Cell Cell I64 I64))
    (define (step-rank goal from step lean)
      (let ((gx (- (Cell-x goal) (Cell-x from))) (gy (- (Cell-y goal) (Cell-y from)))
            (sx (- (Cell-x step) (Cell-x from))) (sy (- (Cell-y step) (Cell-y from))))
        (- (* 1000 (max (abs (- (Cell-x goal) (Cell-x step))) (abs (- (Cell-y goal) (Cell-y step)))))
           (* lean (- (* gx sy) (* gy sx))))))

    ;; ---- Movement ----

    ;; An enemy is engaged when it stands beside its target, or, with none,
    ;; beside the hub.
    (: engaged? (-> World Enemy Bool))
    (define (engaged? world enemy)
      (match (target-mark world enemy)
        ((Some m) (beside? (Enemy-cell enemy) (mark-cell m)))
        ((None) (beside-hub? world (Enemy-cell enemy)))))

    (: beside-hub? (-> World Cell Bool))
    (define (beside-hub? world cell)
      (any? (lambda (neighbor) (hub-cell? (World-hub world) neighbor)) (Cons cell (neighbors cell))))

    ;; On its period an enemy looks around, then, unless it is engaged,
    ;; steps along its route; facing rock or a wall it stays to dig. A
    ;; target it cannot reach is given up for the hub.
    (: march (-> World World))
    (define (march world)
      (fold-left (lambda (world enemy) (if (on-step? world enemy) (step world (think world enemy)) world)) world (World-enemies world)))

    (: step (-> World Enemy World))
    (define (step world enemy)
      (let ((enemy (Enemy-previous-set enemy (Enemy-cell enemy))))
        (if (engaged? world enemy)
            (put-enemy world enemy)
            (let* ((bearing (heading world enemy)) (enemy (Bearing-enemy bearing)) (world (Bearing-world bearing)))
              (match (Bearing-next bearing)
                ((Some cell) (put-enemy world (if (walkable? world cell) (Enemy-cell-set enemy cell) enemy)))
                ((None) (put-enemy world (Enemy-target-set enemy (None)))))))))

    (: on-step? (-> World Enemy Bool))
    (define (on-step? world enemy)
      (= (remainder (+ (World-tick world) (Enemy-id enemy)) (enemy-period (Enemy-behavior enemy))) 0))

    (: put-enemy (-> World Enemy World))
    (define (put-enemy world enemy)
      (World-enemies-set world (map (lambda (e) (if (= (Enemy-id e) (Enemy-id enemy)) enemy e)) (World-enemies world))))

    ;; ---- Excavation ----

    ;; Every other tick an enemy that chose to dig and faces rock or a wall
    ;; on its route strikes it for its dig damage. Rock opens for good once
    ;; its health is gone; a wall is destroyed.
    (: excavate (-> World World))
    (define (excavate world)
      (fold-left (lambda (world enemy) (if (and (on-dig? world enemy) (Plan-digging (Enemy-plan enemy))) (dig world enemy) world))
                 world (World-enemies world)))

    (: on-dig? (-> World Enemy Bool))
    (define (on-dig? world enemy)
      (= (remainder (+ (World-tick world) (Enemy-id enemy)) 2) 0))

    (: dig (-> World Enemy World))
    (define (dig world enemy)
      (if (engaged? world enemy)
          world
          (let* ((bearing (heading world enemy)) (world (put-enemy (Bearing-world bearing) (Bearing-enemy bearing))))
            (match (Bearing-next bearing)
              ((Some cell) (if (walkable? world cell) world (chip world cell (dig-damage enemy))))
              ((None) world)))))

    (: chip (-> World Cell I64 World))
    (define (chip world cell amount)
      (if (walled? world cell)
          (match (building-at world cell)
            ((Some wall) (damage-building world wall amount))
            ((None) world))
          (let ((remaining (- (match (find (lambda (d) (cell=? (Dig-cell d) cell)) (World-digs world)) ((Some d) (Dig-remaining d)) ((None) rock-health)) amount))
                (others (filter (lambda (d) (not (cell=? (Dig-cell d) cell))) (World-digs world))))
            (if (<= remaining 0)
                (open-rock (World-digs-set world others) cell)
                (World-digs-set world (Cons (Dig cell remaining) others))))))

    ;; ---- Turrets ----

    ;; A powered turret fires every eight ticks at the nearest visible enemy
    ;; in range with no rock or wall in the way, so it deals first with what
    ;; is doing damage close by; without one it fires at a nest in range.
    (: fire (-> World World))
    (define (fire world)
      (fold-left fire-one world (filter (lambda (b) (and (turret? b) (built? b) (powered? world (Building-id b))
                                                         (= (remainder (+ (World-tick world) (Building-id b)) 8) 0)))
                                        (World-buildings world))))

    (: turret? (-> Building Bool))
    (define (turret? b)
      (match (Building-kind b) ((Turret) #t) (_ #f)))

    (: fire-one (-> World Building World))
    (define (fire-one world turret)
      (match (choose-enemy world turret)
        ((Some enemy) (hit-enemy world turret enemy))
        ((None) (match (find (lambda (nest) (can-shoot? world turret (Nest-cell nest))) (living-nests world))
                  ((Some nest) (hit-nest world turret nest))
                  ((None) world)))))

    (: can-shoot? (-> World Building Cell Bool))
    (define (can-shoot? world turret cell)
      (and (visible? world cell) (within? cell (Building-cell turret) 6) (clear-shot? world (Building-cell turret) cell)))

    ;; The nearest enemy the turret can shoot; ties go to the oldest.
    (: choose-enemy (-> World Building (Option Enemy)))
    (define (choose-enemy world turret)
      (nearest (filter (lambda (e) (can-shoot? world turret (Enemy-cell e))) (World-enemies world))
               (lambda (e) (distance-squared (Enemy-cell e) (Building-cell turret)))))

    ;; Damage falls from 24 at point blank to 6 at the six-cell range,
    ;; measured in fortieths of a cell, and grows with the turret's level:
    ;; one, one and a half, then two times.
    (: damage (-> Building Cell I64))
    (define (damage turret cell)
      (let ((length (integer-sqrt (* 1600 (distance-squared cell (Building-cell turret))))))
        (quotient (* (+ 6 (quotient (* 18 (- 240 length)) 240)) (+ (Building-level turret) 1)) 2)))

    (: hit-enemy (-> World Building Enemy World))
    (define (hit-enemy world turret enemy)
      (shoot (put-enemy world (Enemy-health-set enemy (- (Enemy-health enemy) (damage turret (Enemy-cell enemy))))) turret (Enemy-cell enemy)))

    ;; A destroyed nest changes the structures: its crystal shows instead.
    (: hit-nest (-> World Building Nest World))
    (define (hit-nest world turret nest)
      (let* ((health (max 0 (- (Nest-health nest) (damage turret (Nest-cell nest)))))
             (world (World-nests-set world (map (lambda (n) (if (= (Nest-front n) (Nest-front nest)) (Nest-health-set n health) n)) (World-nests world)))))
        (shoot (if (= health 0) (structures-changed world) world) turret (Nest-cell nest))))

    ;; A shot leaves a tracer and turns the turret's guns to where it went.
    (: shoot (-> World Building Cell World))
    (define (shoot world turret cell)
      (World-buildings-set (World-shots-set world (Cons (Shot (Building-cell turret) cell (World-tick world)) (World-shots world)))
                           (map (lambda (b) (if (= (Building-id b) (Building-id turret)) (Building-aim-set b (Some cell)) b)) (World-buildings world))))

    ;; ---- Strikes ----

    ;; Every ten ticks each engaged enemy strikes for its rank's damage, and
    ;; each worker with an enemy beside it strikes back.
    (: strike (-> World World))
    (define (strike world)
      (if (= (remainder (World-tick world) 10) 0)
          (fold-left strike-back (fold-left strike-one world (World-enemies world)) (World-workers world))
          world))

    (: strike-one (-> World Enemy World))
    (define (strike-one world enemy)
      (let ((amount (rank-damage (Enemy-rank enemy))) (cell (Enemy-cell enemy)))
        (match (target-mark world enemy)
          ((Some (MarkBuilding b)) (if (beside? cell (Building-cell b)) (damage-building world b amount) world))
          ((Some (MarkWorker w)) (if (beside? cell (Worker-cell w)) (damage-worker world w amount) world))
          ((None) (if (beside-hub? world cell) (damage-hub world amount) world)))))

    ;; A worker still standing strikes the oldest enemy beside it.
    (: strike-back (-> World Worker World))
    (define (strike-back world listed)
      (match (worker world (Worker-id listed))
        ((Some w) (if (> (Worker-health w) 0)
                      (match (find (lambda (e) (beside? (Enemy-cell e) (Worker-cell w))) (World-enemies world))
                        ((Some e) (put-enemy world (Enemy-health-set e (- (Enemy-health e) worker-damage))))
                        ((None) world))
                      world))
        ((None) world)))

    (: damage-building (-> World Building I64 World))
    (define (damage-building world b amount)
      (alert (put-building world (Building-health-set b (max 0 (- (Building-health b) amount)))) (Building-cell b)))

    (: damage-worker (-> World Worker I64 World))
    (define (damage-worker world w amount)
      (alert (put-worker world (Worker-health-set w (max 0 (- (Worker-health w) amount)))) (Worker-cell w)))

    (: damage-hub (-> World I64 World))
    (define (damage-hub world amount)
      (let ((hub (World-hub world)))
        (alert (World-hub-set world (Hub-health-set hub (max 0 (- (Hub-health hub) amount)))) (Hub-cell hub))))

    ;; At most four alerts: a new one replaces any within four cells and any
    ;; older than eight seconds.
    (: alert (-> World Cell World))
    (define (alert world cell)
      (let ((tick (World-tick world)))
        (World-alerts-set world (Cons (Alert cell tick)
                                      (take (filter (lambda (a) (and (<= (- tick (Alert-tick a)) 80) (not (within? (Alert-cell a) cell 4)))) (World-alerts world)) 3)))))

    ;; ---- Settling ----

    ;; Removes the dead and destroyed, counts them, and drops old shots. A
    ;; fallen worker leaves its work's progress for the next.
    (: settle (-> World World))
    (define (settle world)
      (let* ((alive (filter (lambda (e) (> (Enemy-health e) 0)) (World-enemies world)))
             (standing (filter (lambda (b) (> (Building-health b) 0)) (World-buildings world)))
             (world (count-losses world (- (length (World-enemies world)) (length alive)) (- (length (World-buildings world)) (length standing))))
             (world (World-workers-set world (filter (lambda (w) (> (Worker-health w) 0)) (World-workers world))))
             (world (World-shots-set (World-enemies-set world alive) (filter (lambda (s) (> (+ (Shot-tick s) 4) (World-tick world))) (World-shots world)))))
        (if (= (length standing) (length (World-buildings world))) world (rewire (World-buildings-set world standing)))))

    (: count-losses (-> World I64 I64 World))
    (define (count-losses world kills lost)
      (let ((ledger (World-ledger world)))
        (World-ledger-set world (Ledger-lost-set (Ledger-kills-set ledger (+ (Ledger-kills ledger) kills)) (+ (Ledger-lost ledger) lost)))))

    ;; Destroying every nest wins, even on the tick the hub falls. Either way
    ;; the whole map is uncovered for inspection.
    (: judge (-> World World))
    (define (judge world)
      (cond ((null? (living-nests world)) (uncover (World-outcome-set world (Won))))
            ((= (Hub-health (World-hub world)) 0) (uncover (World-outcome-set world (Lost))))
            (else world)))

    ))
