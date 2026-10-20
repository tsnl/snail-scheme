;; The Siegework simulation: a seeded map, a hub, ore deposits, buildings,
;; workers, nests and their waves. Every rule is a total function on World;
;; `advance` runs one tick.
(define-library (siegework world)
  (export
   Terrain
   Open
   Rock
   Deposit
   Deposit-cell
   Deposit-reserve
   Kind
   Hub
   Extractor
   Tower
   Gun
   kind-cost
   kind-name
   Progress
   Waiting
   Assigned
   Built
   Building
   Building-id
   Building-kind
   Building-cell
   Building-hp
   Building-progress
   Building-stock
   Mover
   Mover-cell
   Mover-previous
   Mover-wait
   Task
   Idle
   Fetch
   Carry
   Construct
   Collect
   Return
   Worker
   Worker-mover
   Worker-cargo
   Worker-task
   Enemy
   Enemy-mover
   Enemy-hp
   Nest
   Nest-cell
   Nest-hp
   Shot
   Shot-from
   Shot-to
   Outcome
   Playing
   Won
   Lost
   World
   World-tick
   World-terrain
   World-explored
   World-deposits
   World-buildings
   World-workers
   World-enemies
   World-nests
   World-shots
   World-ore
   World-outcome
   World-message
   World-message-set
   World-seed
   World-version
   World-terrain-version
   new-world
   advance
   place
   recruit
   ticks-until-wave
   worker-speed
   enemy-speed
   nest-health
   kind-health)
  (import
   (lofi base)
   (lofi wire)
   (lofi random)
   (siegework grid))
  (begin

    ;; ---- Map ----

    (enum Terrain
      (Open)
      (Rock)
      (deriving Serialize Deserialize))

    (struct Deposit
      ((cell Cell)
       (reserve I64))
      (deriving Serialize Deserialize))

    ;; ---- Buildings ----

    (enum Kind
      (Hub)
      (Extractor)
      (Tower)
      (Gun)
      (deriving Serialize Deserialize))

    ;; A site waits for a worker to bring its kit from the hub, then is built.
    (enum Progress
      (Waiting)
      (Assigned ((worker I64)))
      (Built)
      (deriving Serialize Deserialize))

    ;; `stock` is an extractor's mined ore; `cooldown` paces mining and guns.
    (struct Building
      ((id I64)
       (kind Kind)
       (cell Cell)
       (hp I64)
       (progress Progress)
       (stock I64)
       (cooldown I64))
      (deriving Serialize Deserialize))

    (: kind-cost (-> Kind I64))
    (define (kind-cost kind)
      (match kind
        ((Hub) 0)
        ((Extractor) 25)
        ((Tower) 25)
        ((Gun) 50)))

    (: kind-health (-> Kind I64))
    (define (kind-health kind)
      (match kind
        ((Hub) 400)
        ((Extractor) 100)
        ((Tower) 120)
        ((Gun) 150)))

    ;; How far a built building reveals the map.
    (: kind-sight (-> Kind I64))
    (define (kind-sight kind)
      (match kind
        ((Hub) 6)
        ((Extractor) 3)
        ((Tower) 9)
        ((Gun) 4)))

    (: kind-name (-> Kind String))
    (define (kind-name kind)
      (match kind
        ((Hub) "Hub")
        ((Extractor) "Extractor")
        ((Tower) "Tower")
        ((Gun) "Gun")))

    ;; ---- Units ----

    ;; A unit walks its path one cell at a time, waiting between steps.
    (struct Mover
      ((cell Cell)
       (previous Cell)
       (path (List Cell))
       (wait I64))
      (deriving Serialize Deserialize))

    ;; What a worker is doing, and toward which building.
    (enum Task
      (Idle)
      (Fetch ((site I64)))
      (Carry ((site I64)))
      (Construct ((site I64) (remaining I64)))
      (Collect ((extractor I64)))
      (Return)
      (deriving Serialize Deserialize))

    (struct Worker
      ((id I64)
       (mover Mover)
       (cargo I64)
       (task Task))
      (deriving Serialize Deserialize))

    (struct Enemy
      ((id I64)
       (mover Mover)
       (hp I64)
       (cooldown I64)
       (target I64))
      (deriving Serialize Deserialize))

    (struct Nest
      ((id I64)
       (cell Cell)
       (hp I64))
      (deriving Serialize Deserialize))

    ;; A shot is drawn for a few ticks after a gun fires.
    (struct Shot
      ((from Cell)
       (to Cell)
       (age I64))
      (deriving Serialize Deserialize))

    (enum Outcome
      (Playing)
      (Won)
      (Lost)
      (deriving Serialize Deserialize))

    ;; ---- World ----

    ;; `version` changes whenever buildings, deposits or nests change, and
    ;; `terrain-version` whenever more of the map is revealed, so a view can
    ;; reuse what it drew.
    (struct World
      ((seed I64)
       (tick I64)
       (terrain (Vector Terrain))
       (explored (Vector Bool))
       (deposits (List Deposit))
       (buildings (List Building))
       (workers (List Worker))
       (enemies (List Enemy))
       (nests (List Nest))
       (shots (List Shot))
       (ore I64)
       (next-id I64)
       (outcome Outcome)
       (message String)
       (version I64)
       (terrain-version I64))
      (deriving Serialize Deserialize))

    (: worker-speed I64)
    (define worker-speed 3)

    (: enemy-speed I64)
    (define enemy-speed 5)

    (: nest-health I64)
    (define nest-health 600)

    (: first-wave I64)
    (define first-wave 450)

    (: wave-interval I64)
    (define wave-interval 300)

    (: hub-cell Cell)
    (define hub-cell (Cell 20 20))

    (: changed (-> World World))
    (define (changed world)
      (World-version-set world (+ (World-version world) 1)))

    (: fresh-id (-> World (Pair I64 World)))
    (define (fresh-id world)
      (Pair (World-next-id world) (World-next-id-set world (+ (World-next-id world) 1))))

    (: open-cells (-> World (Vector Bool)))
    (define (open-cells world)
      (vector-map (lambda (terrain) (match terrain ((Open) #t) ((Rock) #f))) (World-terrain world)))

    (: route (-> World Cell (-> Cell Bool) (Option (List Cell))))
    (define (route world start goal?)
      (find-path (open-cells world) start goal?))

    ;; ---- Generation ----

    ;; Each cell has its own pseudo-random value derived from the seed, so
    ;; generation needs no generator threaded through it.
    (: noise (-> I64 I64 I64 I64))
    (define (noise seed salt bound)
      (random-below (make-random (+ (* seed 1000003) salt)) bound))

    (: new-world (-> I64 World))
    (define (new-world seed)
      (let* ((rough (vector-generate (* map-size map-size)
                                     (lambda (index)
                                       (or (< (distance-squared (index-cell index) hub-cell) 10) (>= (noise seed index 100) 20)))))
             (open (reachable rough hub-cell))
             (terrain (vector-map (lambda (open?) (if open? (Open) (Rock))) open))
             (deposits (place-deposits seed open))
             (nests (place-nests seed open))
             (world (World seed 0 terrain (vector-generate (* map-size map-size) (lambda (index) #f))
                           deposits (list (Building 1 (Hub) hub-cell (kind-health (Hub)) (Built) 0 0))
                           (map (lambda (id) (Worker id (Mover hub-cell hub-cell (Nil) 0) 0 (Idle))) (list 2 3 4))
                           (Nil) nests (Nil) 60 100 (Playing) "Place an extractor on the nearby ore." 0 0)))
        (reveal world)))

    ;; Picks cells from a seeded sequence of candidates, accepting each one
    ;; that `accept?` allows given the cells already chosen.
    (: choose-cells (-> I64 I64 I64 (-> Cell (List Cell) Bool) (List Cell)))
    (define (choose-cells seed salt count accept?)
      (let loop ((attempt 0) (chosen (Nil)))
        (if (or (= (length chosen) count) (= attempt 5000))
            (reverse chosen)
            (let ((cell (Cell (noise seed (+ salt (* 2 attempt)) map-size) (noise seed (+ salt (+ 1 (* 2 attempt))) map-size))))
              (loop (+ attempt 1) (if (accept? cell chosen) (Cons cell chosen) chosen))))))

    (: between? (-> I64 I64 I64 Bool))
    (define (between? low value high)
      (and (<= low value) (<= value high)))

    (: far-from-all? (-> Cell (List Cell) I64 Bool))
    (define (far-from-all? cell others distance)
      (every? (lambda (other) (>= (distance-squared cell other) (* distance distance))) others))

    ;; One starter deposit near the hub, and three richer ones farther out.
    (: place-deposits (-> I64 (Vector Bool) (List Deposit)))
    (define (place-deposits seed open)
      (let ((starter (choose-cells seed 100000 1
                                   (lambda (cell chosen)
                                     (and (vector-ref open (cell-index cell))
                                          (between? 16 (distance-squared cell hub-cell) 36)))))
            (outer (choose-cells seed 200000 3
                                 (lambda (cell chosen)
                                   (and (vector-ref open (cell-index cell))
                                        (between? 100 (distance-squared cell hub-cell) 300)
                                        (far-from-all? cell chosen 8))))))
        (append (map (lambda (cell) (Deposit cell 400)) starter)
                (map (lambda (cell) (Deposit cell (+ 600 (* 200 (noise seed (cell-index cell) 4))))) outer))))

    (: place-nests (-> I64 (Vector Bool) (List Nest)))
    (define (place-nests seed open)
      (let ((cells (choose-cells seed 300000 3
                                 (lambda (cell chosen)
                                   (and (vector-ref open (cell-index cell))
                                        (>= (distance-squared cell hub-cell) 225)
                                        (far-from-all? cell chosen 12))))))
        (map-indexed (lambda (index cell) (Nest (+ 1000 index) cell nest-health)) cells)))

    ;; Marks every cell within sight of a built building as explored.
    (: reveal (-> World World))
    (define (reveal world)
      (let* ((sights (filter-map (lambda (building)
                                   (match (Building-progress building)
                                     ((Built) (Some (Pair (Building-cell building) (kind-sight (Building-kind building)))))
                                     (_ (None))))
                                 (World-buildings world)))
             (explored (vector-generate (* map-size map-size)
                                        (lambda (index)
                                          (or (vector-ref (World-explored world) index)
                                              (any? (lambda (sight)
                                                      (<= (distance-squared (index-cell index) (Pair-first sight))
                                                          (* (Pair-second sight) (Pair-second sight))))
                                                    sights))))))
        (World-terrain-version-set (World-explored-set world explored) (+ (World-terrain-version world) 1))))

    (: filter-map (All (A B) (-> (-> A (Option B)) (List A) (List B))))
    (define (filter-map f items)
      (fold-right (lambda (item kept) (match (f item) ((Some value) (Cons value kept)) ((None) kept))) (Nil) items))

    ;; ---- Lookups and replacements ----

    (: building (-> World I64 (Option Building)))
    (define (building world id)
      (find (lambda (b) (= (Building-id b) id)) (World-buildings world)))

    (: put-building (-> World Building World))
    (define (put-building world building)
      (changed (World-buildings-set world (map (lambda (b) (if (= (Building-id b) (Building-id building)) building b))
                                               (World-buildings world)))))

    (: put-worker (-> World Worker World))
    (define (put-worker world worker)
      (World-workers-set world (map (lambda (w) (if (= (Worker-id w) (Worker-id worker)) worker w)) (World-workers world))))

    (: put-enemy (-> World Enemy World))
    (define (put-enemy world enemy)
      (World-enemies-set world (map (lambda (e) (if (= (Enemy-id e) (Enemy-id enemy)) enemy e)) (World-enemies world))))

    (: deposit-at (-> World Cell (Option Deposit)))
    (define (deposit-at world cell)
      (find (lambda (deposit) (cell=? (Deposit-cell deposit) cell)) (World-deposits world)))

    (: built? (-> Building Bool))
    (define (built? building)
      (match (Building-progress building)
        ((Built) #t)
        (_ #f)))

    ;; ---- Movement ----

    (: start-walk (-> Mover (List Cell) Mover))
    (define (start-walk mover path)
      (Mover-path-set (Mover-previous-set mover (Mover-cell mover)) path))

    ;; Waits, or steps to the next cell of the path. #f once arrived.
    (: walk (-> Mover I64 (Option Mover)))
    (define (walk mover speed)
      (cond ((> (Mover-wait mover) 0) (Some (Mover-wait-set mover (- (Mover-wait mover) 1))))
            (else (match (Mover-path mover)
                    ((Nil) (None))
                    ((Cons next rest) (Some (Mover next (Mover-cell mover) rest (- speed 1))))))))

    ;; ---- Mining ----

    ;; Every ten ticks each built extractor moves one ore from its deposit
    ;; into its stock, which holds at most twenty.
    (: mine (-> World World))
    (define (mine world)
      (if (= (remainder (World-tick world) 10) 0)
          (fold-left mine-at world (filter (lambda (b) (and (built? b) (match (Building-kind b) ((Extractor) #t) (_ #f))))
                                           (World-buildings world)))
          world))

    (: mine-at (-> World Building World))
    (define (mine-at world extractor)
      (match (deposit-at world (Building-cell extractor))
        ((Some deposit)
         (if (and (> (Deposit-reserve deposit) 0) (< (Building-stock extractor) 20))
             (put-building (World-deposits-set world (map (lambda (d) (if (cell=? (Deposit-cell d) (Deposit-cell deposit))
                                                                          (Deposit-reserve-set d (- (Deposit-reserve d) 1))
                                                                          d))
                                                          (World-deposits world)))
                           (Building-stock-set extractor (+ (Building-stock extractor) 1)))
             world))
        ((None) world)))

    ;; ---- Workers ----

    ;; An idle worker returns any ore it carries, then takes the oldest site
    ;; waiting for a kit, then collects from the fullest extractor that no
    ;; other worker is collecting from.
    (: assign (-> World Worker World))
    (define (assign world worker)
      (let ((cell (Mover-cell (Worker-mover worker))))
        (if (> (Worker-cargo worker) 0)
            (send world worker (Return) hub-cell)
            (match (find (lambda (b) (match (Building-progress b) ((Waiting) #t) (_ #f))) (World-buildings world))
              ((Some site)
               (match (route world cell (lambda (c) (cell=? c hub-cell)))
                 ((Some path) (put-worker (put-building world (Building-progress-set site (Assigned (Worker-id worker))))
                                          (Worker-task-set (Worker-mover-set worker (start-walk (Worker-mover worker) path))
                                                           (Fetch (Building-id site)))))
                 ((None) world)))
              ((None)
               (match (fullest-extractor world)
                 ((Some extractor) (send world worker (Collect (Building-id extractor)) (Building-cell extractor)))
                 ((None) world)))))))

    (: send (-> World Worker Task Cell World))
    (define (send world worker task destination)
      (match (route world (Mover-cell (Worker-mover worker)) (lambda (c) (cell=? c destination)))
        ((Some path) (put-worker world (Worker-task-set (Worker-mover-set worker (start-walk (Worker-mover worker) path)) task)))
        ((None) (put-worker world (Worker-task-set worker (Idle))))))

    (: fullest-extractor (-> World (Option Building)))
    (define (fullest-extractor world)
      (let ((claimed (filter-map (lambda (w) (match (Worker-task w) ((Collect id) (Some id)) (_ (None)))) (World-workers world))))
        (fold-left (lambda (best b)
                     (if (and (built? b) (>= (Building-stock b) 5) (not (member? (Building-id b) claimed))
                              (match best ((Some other) (> (Building-stock b) (Building-stock other))) ((None) #t)))
                         (Some b) best))
                   (None) (World-buildings world))))

    (: update-workers (-> World World))
    (define (update-workers world)
      (fold-left (lambda (world id)
                   (match (find (lambda (w) (= (Worker-id w) id)) (World-workers world))
                     ((Some worker) (update-worker world worker))
                     ((None) world)))
                 world (map Worker-id (World-workers world))))

    (: update-worker (-> World Worker World))
    (define (update-worker world worker)
      (let ((world (match (Worker-task worker) ((Idle) (assign world worker)) (_ world))))
        (match (find (lambda (w) (= (Worker-id w) (Worker-id worker))) (World-workers world))
          ((Some worker)
           (match (walk (Worker-mover worker) worker-speed)
             ((Some mover) (put-worker world (Worker-mover-set worker mover)))
             ((None) (arrive world worker))))
          ((None) world))))

    ;; What a worker does on reaching the end of its path.
    (: arrive (-> World Worker World))
    (define (arrive world worker)
      (match (Worker-task worker)
        ((Idle) world)
        ((Fetch site)
         (match (building world site)
           ((Some b) (send world worker (Carry site) (Building-cell b)))
           ((None) (put-worker world (Worker-task-set worker (Idle))))))
        ((Carry site) (put-worker world (Worker-task-set worker (Construct site 20))))
        ((Construct site remaining)
         (match (building world site)
           ((Some b)
            (if (> remaining 1)
                (put-worker world (Worker-task-set worker (Construct site (- remaining 1))))
                (put-worker (reveal (put-building world (Building-progress-set b (Built)))) (Worker-task-set worker (Idle)))))
           ((None) (put-worker world (Worker-task-set worker (Idle))))))
        ((Collect id)
         (match (building world id)
           ((Some b)
            (let ((taken (min (Building-stock b) 10)))
              (send (put-building world (Building-stock-set b (- (Building-stock b) taken)))
                    (Worker-cargo-set worker taken) (Return) hub-cell)))
           ((None) (put-worker world (Worker-task-set worker (Idle))))))
        ((Return)
         (put-worker (World-ore-set world (+ (World-ore world) (Worker-cargo worker)))
                     (Worker-task-set (Worker-cargo-set worker 0) (Idle))))))

    ;; ---- Waves ----

    (: ticks-until-wave (-> World I64))
    (define (ticks-until-wave world)
      (let ((tick (World-tick world)))
        (if (< tick first-wave)
            (- first-wave tick)
            (- wave-interval (remainder (- tick first-wave) wave-interval)))))

    ;; Each wave, every nest sends one more enemy than the last time, each a
    ;; little tougher.
    (: spawn-waves (-> World World))
    (define (spawn-waves world)
      (let ((tick (World-tick world)))
        (if (and (>= tick first-wave) (= (remainder (- tick first-wave) wave-interval) 0))
            (let ((wave (+ 1 (quotient (- tick first-wave) wave-interval))))
              (fold-left (lambda (world nest)
                           (fold-left (lambda (world index) (spawn world (Nest-cell nest) (+ 30 (* 10 wave))))
                                      world (iota (min 8 wave))))
                         world (World-nests world)))
            world)))

    (: spawn (-> World Cell I64 World))
    (define (spawn world cell hp)
      (match (fresh-id world)
        ((Pair id world)
         (World-enemies-set world (Cons (Enemy id (Mover cell cell (Nil) 0) hp 0 0) (World-enemies world))))))

    ;; ---- Enemies ----

    ;; An enemy walks to the nearest building and strikes it every ten ticks.
    (: update-enemies (-> World World))
    (define (update-enemies world)
      (fold-left update-enemy world (World-enemies world)))

    (: update-enemy (-> World Enemy World))
    (define (update-enemy world enemy)
      (let ((cell (Mover-cell (Enemy-mover enemy))))
        (match (building world (Enemy-target enemy))
          ((Some target)
           (if (adjacent? cell (Building-cell target))
               (strike world enemy target)
               (match (walk (Enemy-mover enemy) enemy-speed)
                 ((Some mover) (put-enemy world (Enemy-mover-set enemy mover)))
                 ((None) (put-enemy world (Enemy-target-set enemy 0))))))
          ((None) (choose-target world enemy)))))

    (: choose-target (-> World Enemy World))
    (define (choose-target world enemy)
      (let ((cell (Mover-cell (Enemy-mover enemy))))
        (match (fold-left (lambda (best b)
                            (match best
                              ((Some other) (if (< (distance-squared cell (Building-cell b)) (distance-squared cell (Building-cell other))) (Some b) best))
                              ((None) (Some b))))
                          (None) (World-buildings world))
          ((Some target)
           (match (route world cell (lambda (c) (adjacent? c (Building-cell target))))
             ((Some path) (put-enemy world (Enemy-target-set (Enemy-mover-set enemy (start-walk (Enemy-mover enemy) path))
                                                             (Building-id target))))
             ((None) world)))
          ((None) world))))

    (: strike (-> World Enemy Building World))
    (define (strike world enemy target)
      (if (> (Enemy-cooldown enemy) 0)
          (put-enemy world (Enemy-cooldown-set enemy (- (Enemy-cooldown enemy) 1)))
          (put-building (put-enemy world (Enemy-cooldown-set enemy 10)) (Building-hp-set target (- (Building-hp target) 8)))))

    ;; ---- Guns ----

    ;; A built gun fires every eight ticks at the nearest enemy within five
    ;; cells, or else at a nest in range.
    (: fire-guns (-> World World))
    (define (fire-guns world)
      (fold-left fire world (filter (lambda (b) (and (built? b) (match (Building-kind b) ((Gun) #t) (_ #f)))) (World-buildings world))))

    (: fire (-> World Building World))
    (define (fire world gun)
      (let ((cell (Building-cell gun)))
        (cond ((> (Building-cooldown gun) 0) (put-building world (Building-cooldown-set gun (- (Building-cooldown gun) 1))))
              (else
               (match (nearest (filter (lambda (e) (<= (distance-squared cell (Mover-cell (Enemy-mover e))) 25)) (World-enemies world))
                               (lambda (e) (distance-squared cell (Mover-cell (Enemy-mover e)))))
                 ((Some enemy)
                  (shoot (put-enemy world (Enemy-hp-set enemy (- (Enemy-hp enemy) 25))) gun (Mover-cell (Enemy-mover enemy))))
                 ((None)
                  (match (find (lambda (n) (<= (distance-squared cell (Nest-cell n)) 25)) (World-nests world))
                    ((Some nest)
                     (shoot (changed (World-nests-set world (map (lambda (n) (if (= (Nest-id n) (Nest-id nest)) (Nest-hp-set n (- (Nest-hp n) 25)) n))
                                                                 (World-nests world))))
                            gun (Nest-cell nest)))
                    ((None) world))))))))

    (: shoot (-> World Building Cell World))
    (define (shoot world gun target)
      (put-building (World-shots-set world (Cons (Shot (Building-cell gun) target 0) (World-shots world)))
                    (Building-cooldown-set gun 8)))

    (: nearest (All (A) (-> (List A) (-> A I64) (Option A))))
    (define (nearest items distance)
      (fold-left (lambda (best item)
                   (match best
                     ((Some other) (if (< (distance item) (distance other)) (Some item) best))
                     ((None) (Some item))))
                 (None) items))

    ;; ---- Ticks ----

    ;; Removes what was destroyed and decides whether the game is over.
    (: settle (-> World World))
    (define (settle world)
      (let* ((buildings (filter (lambda (b) (> (Building-hp b) 0)) (World-buildings world)))
             (nests (filter (lambda (n) (> (Nest-hp n) 0)) (World-nests world)))
             (world (World-shots-set (World-enemies-set world (filter (lambda (e) (> (Enemy-hp e) 0)) (World-enemies world)))
                                     (filter (lambda (s) (< (Shot-age s) 3)) (map (lambda (s) (Shot-age-set s (+ (Shot-age s) 1))) (World-shots world)))))
             (world (if (and (= (length buildings) (length (World-buildings world))) (= (length nests) (length (World-nests world))))
                        world
                        (changed (World-nests-set (World-buildings-set world buildings) nests)))))
        (cond ((not (any? (lambda (b) (match (Building-kind b) ((Hub) #t) (_ #f))) buildings))
               (World-message-set (World-outcome-set world (Lost)) "The hub has fallen."))
              ((null? nests) (World-message-set (World-outcome-set world (Won)) "Every nest is destroyed. Victory!"))
              (else world))))

    (: advance (-> World World))
    (define (advance world)
      (match (World-outcome world)
        ((Playing)
         (settle (fire-guns (update-enemies (spawn-waves (update-workers (mine (World-tick-set world (+ (World-tick world) 1)))))))))
        (_ world)))

    ;; ---- Orders ----

    ;; Places a site for `kind` at `cell`, paying its cost now.
    (: place (-> World Kind Cell (Result World String)))
    (define (place world kind cell)
      (cond ((not (in-bounds? cell)) (Err "Outside the map."))
            ((not (vector-ref (World-explored world) (cell-index cell))) (Err "That ground is unexplored."))
            ((match (vector-ref (World-terrain world) (cell-index cell)) ((Rock) #t) ((Open) #f)) (Err "Rock is in the way."))
            ((any? (lambda (b) (cell=? (Building-cell b) cell)) (World-buildings world)) (Err "Something is already built there."))
            ((match kind ((Extractor) (match (deposit-at world cell) ((None) #t) (_ #f))) (_ #f))
             (Err "Extractors go on ore deposits."))
            ((< (World-ore world) (kind-cost kind)) (Err "Not enough ore."))
            (else
             (match (fresh-id world)
               ((Pair id world)
                (Ok (changed (World-message-set
                              (World-ore-set (World-buildings-set world (append (World-buildings world)
                                                                                (list (Building id kind cell (kind-health kind) (Waiting) 0 0))))
                                             (- (World-ore world) (kind-cost kind)))
                              (string-append (kind-name kind) " ordered.")))))))))

    (: recruit (-> World (Result World String)))
    (define (recruit world)
      (if (< (World-ore world) 40)
          (Err "A worker costs 40 ore.")
          (match (fresh-id world)
            ((Pair id world)
             (Ok (World-message-set
                  (World-ore-set (World-workers-set world (Cons (Worker id (Mover hub-cell hub-cell (Nil) 0) 0 (Idle)) (World-workers world)))
                                 (- (World-ore world) 40))
                  "A new worker joins the colony."))))))

    ))
