;; The Siegework simulation: a seeded map, a hub, ore deposits, buildings,
;; workers, nests and their waves. Every rule is a total function on World,
;; and `advance` runs one tick.
;;
;; Time is the world's tick: periodic rules fire on multiples of their
;; period, and a duration is a deadline tick, so no unit keeps a countdown.
;; Ids only increase, so the oldest thing has the smallest id.
(define-library (siegework world)
  (export
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
   Stage
   Site
   Built
   Building
   Building-id
   Building-kind
   Building-stage
   Building-cell
   Building-health
   Building-stock
   Mover
   Mover-cell
   Mover-previous
   Job
   Idle
   Deliver
   FetchKit
   CarryKit
   Construct
   Collect
   Worker
   Worker-mover
   Worker-ore
   Worker-job
   Enemy
   Enemy-mover
   Enemy-health
   Nest
   Nest-cell
   Nest-health
   Shot
   Shot-from
   Shot-to
   Outcome
   Playing
   Won
   Lost
   World
   World-seed
   World-tick
   World-land
   world-hub
   World-explored
   World-deposits
   World-buildings
   World-workers
   World-enemies
   World-nests
   World-shots
   World-ore
   World-ore-set
   World-outcome
   World-message
   World-message-set
   World-explored-version
   World-structure-version
   new-world
   advance
   place
   recruit
   ticks-until-wave
   worker-period
   enemy-period)
  (import
   (lofi base)
   (lofi wire)
   (siegework grid)
   (siegework terrain))
  (begin

    ;; ---- Map ----

    ;; At most one deposit sits on a cell.
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

    ;; An ordered building is a site until a worker builds it; only built
    ;; buildings mine, shoot or reveal, but enemies attack both.
    (enum Stage
      (Site)
      (Built)
      (deriving Serialize Deserialize))

    ;; `stock` is the ore an extractor has mined; it is zero for others.
    (struct Building
      ((id I64)
       (kind Kind)
       (stage Stage)
       (cell Cell)
       (health I64)
       (stock I64))
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
        ((Hub) 600)
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

    ;; A unit steps to the next cell of its path on each multiple of its
    ;; period; `previous` is where it stepped from, for drawing it between.
    (struct Mover
      ((cell Cell)
       (previous Cell)
       (path (List Cell)))
      (deriving Serialize Deserialize))

    ;; A worker's job names the building it works toward. A site is claimed
    ;; exactly when some worker's job names it, so a claim cannot outlive its
    ;; job. Every job ends in Idle, and the worker then decides again.
    (enum Job
      (Idle)
      (Deliver)
      (FetchKit ((site I64)))
      (CarryKit ((site I64)))
      (Construct ((site I64) (until I64)))
      (Collect ((extractor I64)))
      (deriving Serialize Deserialize))

    (struct Worker
      ((id I64)
       (mover Mover)
       (ore I64)
       (job Job))
      (deriving Serialize Deserialize))

    (struct Enemy
      ((id I64)
       (mover Mover)
       (health I64)
       (target (Option I64)))
      (deriving Serialize Deserialize))

    (struct Nest
      ((id I64)
       (cell Cell)
       (health I64))
      (deriving Serialize Deserialize))

    ;; A shot is drawn until its deadline after a gun fires.
    (struct Shot
      ((from Cell)
       (to Cell)
       (until I64))
      (deriving Serialize Deserialize))

    (enum Outcome
      (Playing)
      (Won)
      (Lost)
      (deriving Serialize Deserialize))

    ;; ---- World ----

    ;; The two versions change whenever the explored area, or the buildings,
    ;; deposits and nests, change, so a view can reuse what it drew.
    (struct World
      ((seed I64)
       (tick I64)
       (land Land)
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
       (explored-version I64)
       (structure-version I64))
      (deriving Serialize Deserialize))

    (: worker-period I64)
    (define worker-period 3)

    (: enemy-period I64)
    (define enemy-period 5)

    (: first-wave I64)
    (define first-wave 600)

    (: wave-interval I64)
    (define wave-interval 300)

    (: world-hub (-> World Cell))
    (define (world-hub world)
      (Land-hub (World-land world)))

    (: on-period? (-> World I64 Bool))
    (define (on-period? world period)
      (= (remainder (World-tick world) period) 0))

    (: structures-changed (-> World World))
    (define (structures-changed world)
      (World-structure-version-set world (+ (World-structure-version world) 1)))

    (: fresh-id (-> World (Pair I64 World)))
    (define (fresh-id world)
      (Pair (World-next-id world) (World-next-id-set world (+ (World-next-id world) 1))))

    (: route (-> World Cell (-> Cell Bool) (Option (List Cell))))
    (define (route world start goal?)
      (find-path (vector-map (lambda (ground) (match ground ((Grass) #t) (_ #f))) (Land-ground (World-land world))) start goal?))

    ;; ---- Generation ----

    ;; The land comes from the seed; each crystal site becomes a deposit
    ;; holding its full reserve, and each front a nest.
    (: new-world (-> I64 World))
    (define (new-world seed)
      (let* ((land (new-land (land-seed seed))) (hub (Land-hub land))
             (world (World seed 0 land
                           (vector-generate (* map-size map-size) (lambda (index) #f))
                           (map (lambda (site) (Deposit (Site-cell site) (* reserve-per-rate (Site-rate site)))) (Land-sites land))
                           (list (Building 1 (Hub) (Built) hub (kind-health (Hub)) 0))
                           (map (lambda (id) (Worker id (Mover hub hub (Nil)) 0 (Idle))) (list 2 3 4))
                           (Nil) (map-indexed (lambda (index cell) (Nest (+ 1000 index) cell 900)) (Land-fronts land))
                           (Nil) 60 100 (Playing) "Place an extractor on the nearby ore." 0 0)))
        (reveal world)))

    ;; Marks every cell within sight of a built building as explored.
    (: reveal (-> World World))
    (define (reveal world)
      (let* ((sights (filter (lambda (b) (match (Building-stage b) ((Built) #t) ((Site) #f))) (World-buildings world)))
             (explored (vector-generate (* map-size map-size)
                                        (lambda (index)
                                          (or (vector-ref (World-explored world) index)
                                              (any? (lambda (b)
                                                      (<= (distance-squared (index-cell index) (Building-cell b))
                                                          (* (kind-sight (Building-kind b)) (kind-sight (Building-kind b)))))
                                                    sights))))))
        (World-explored-version-set (World-explored-set world explored) (+ (World-explored-version world) 1))))

    ;; ---- Lookups and replacements ----

    (: building (-> World I64 (Option Building)))
    (define (building world id)
      (find (lambda (b) (= (Building-id b) id)) (World-buildings world)))

    (: put-building (-> World Building World))
    (define (put-building world building)
      (structures-changed
       (World-buildings-set world (map (lambda (b) (if (= (Building-id b) (Building-id building)) building b))
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

    (: is-site? (-> World I64 Bool))
    (define (is-site? world id)
      (match (building world id)
        ((Some b) (match (Building-stage b) ((Site) #t) ((Built) #f)))
        ((None) #f)))

    (: built-extractor? (-> Building Bool))
    (define (built-extractor? b)
      (and (match (Building-kind b) ((Extractor) #t) (_ #f)) (match (Building-stage b) ((Built) #t) ((Site) #f))))

    ;; ---- Movement ----

    ;; Steps along the path on a multiple of the unit's period; a unit with no
    ;; path stays, and is then drawn standing still.
    (: walk (-> World Mover I64 Mover))
    (define (walk world mover period)
      (cond ((not (on-period? world period)) mover)
            (else (match (Mover-path mover)
                    ((Nil) (Mover-previous-set mover (Mover-cell mover)))
                    ((Cons next rest) (Mover next (Mover-cell mover) rest))))))

    (: arrived? (-> Mover Bool))
    (define (arrived? mover)
      (null? (Mover-path mover)))

    ;; ---- Mining ----

    ;; Every ten ticks each built extractor moves one ore from its deposit
    ;; into its stock, which holds at most twenty.
    (: mine (-> World World))
    (define (mine world)
      (if (on-period? world 10)
          (fold-left mine-at world (filter built-extractor? (World-buildings world)))
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

    ;; Workers act one at a time, each seeing the world the previous left, so
    ;; two workers never claim the same site or extractor.
    (: update-workers (-> World World))
    (define (update-workers world)
      (fold-left (lambda (world id)
                   (match (find (lambda (w) (= (Worker-id w) id)) (World-workers world))
                     ((Some worker) (update-worker world worker))
                     ((None) world)))
                 world (map Worker-id (World-workers world))))

    ;; A job whose building is gone is abandoned; the worker keeps its ore.
    (: update-worker (-> World Worker World))
    (define (update-worker world worker)
      (let ((worker (if (target-exists? world (Worker-job worker))
                        worker
                        (Worker-job-set (Worker-mover-set worker (Mover-path-set (Worker-mover worker) (Nil))) (Idle)))))
        (match (Worker-job worker)
          ((Idle) (put-worker world (decide world worker)))
          (_ (let ((worker (Worker-mover-set worker (walk world (Worker-mover worker) worker-period))))
               (if (arrived? (Worker-mover worker)) (arrive world worker) (put-worker world worker)))))))

    (: target-exists? (-> World Job Bool))
    (define (target-exists? world job)
      (match job
        ((FetchKit site) (is-site? world site))
        ((CarryKit site) (is-site? world site))
        ((Construct site _) (is-site? world site))
        ((Collect extractor) (match (building world extractor) ((Some _) #t) ((None) #f)))
        (_ #t)))

    ;; An idle worker returns any ore it carries, then fetches the kit for the
    ;; oldest unclaimed site, then collects from the fullest extractor that
    ;; no other worker is collecting from.
    (: decide (-> World Worker Worker))
    (define (decide world worker)
      (cond ((> (Worker-ore worker) 0) (start-job world worker (Deliver) (world-hub world)))
            (else (match (oldest-unclaimed-site world)
                    ((Some site) (start-job world worker (FetchKit (Building-id site)) (world-hub world)))
                    ((None) (match (fullest-free-extractor world)
                              ((Some extractor) (start-job world worker (Collect (Building-id extractor)) (Building-cell extractor)))
                              ((None) worker)))))))

    (: start-job (-> World Worker Job Cell Worker))
    (define (start-job world worker job destination)
      (match (route world (Mover-cell (Worker-mover worker)) (lambda (cell) (cell=? cell destination)))
        ((Some path) (Worker-job-set (Worker-mover-set worker (Mover-path-set (Worker-mover worker) path)) job))
        ((None) worker)))

    (: claimed (-> World (List I64)))
    (define (claimed world)
      (filter-map (lambda (w)
                    (match (Worker-job w)
                      ((FetchKit site) (Some site))
                      ((CarryKit site) (Some site))
                      ((Construct site _) (Some site))
                      ((Collect extractor) (Some extractor))
                      (_ (None))))
                  (World-workers world)))

    (: oldest-unclaimed-site (-> World (Option Building)))
    (define (oldest-unclaimed-site world)
      (let ((claimed (claimed world)))
        (find (lambda (b) (and (is-site? world (Building-id b)) (not (member? (Building-id b) claimed))))
              (World-buildings world))))

    (: fullest-free-extractor (-> World (Option Building)))
    (define (fullest-free-extractor world)
      (let ((claimed (claimed world)))
        (fold-left (lambda (best b)
                     (if (and (built-extractor? b) (>= (Building-stock b) 5) (not (member? (Building-id b) claimed))
                              (match best ((Some other) (> (Building-stock b) (Building-stock other))) ((None) #t)))
                         (Some b) best))
                   (None) (World-buildings world))))

    (: filter-map (All (A B) (-> (-> A (Option B)) (List A) (List B))))
    (define (filter-map f items)
      (fold-right (lambda (item kept) (match (f item) ((Some value) (Cons value kept)) ((None) kept))) (Nil) items))

    ;; What a worker does at the end of its path.
    (: arrive (-> World Worker World))
    (define (arrive world worker)
      (match (Worker-job worker)
        ((Deliver) (put-worker (World-ore-set world (+ (World-ore world) (Worker-ore worker)))
                               (Worker-job-set (Worker-ore-set worker 0) (Idle))))
        ((FetchKit site)
         (match (building world site)
           ((Some b) (put-worker world (start-job world worker (CarryKit site) (Building-cell b))))
           ((None) (put-worker world (Worker-job-set worker (Idle))))))
        ((CarryKit site) (put-worker world (Worker-job-set worker (Construct site (+ (World-tick world) 20)))))
        ((Construct site until)
         (if (< (World-tick world) until)
             (put-worker world worker)
             (put-worker (complete world site) (Worker-job-set worker (Idle)))))
        ((Collect extractor) (collect world worker extractor))
        ((Idle) (put-worker world worker))))

    (: complete (-> World I64 World))
    (define (complete world site)
      (match (building world site)
        ((Some b) (reveal (put-building world (Building-stage-set b (Built)))))
        ((None) world)))

    (: collect (-> World Worker I64 World))
    (define (collect world worker extractor)
      (match (building world extractor)
        ((Some b)
         (let ((taken (min (Building-stock b) 10)))
           (put-worker (put-building world (Building-stock-set b (- (Building-stock b) taken)))
                       (Worker-job-set (Worker-ore-set worker (+ (Worker-ore worker) taken)) (Idle)))))
        ((None) (put-worker world (Worker-job-set worker (Idle))))))

    ;; ---- Waves ----

    (: ticks-until-wave (-> World I64))
    (define (ticks-until-wave world)
      (let ((tick (World-tick world)))
        (if (< tick first-wave)
            (- first-wave tick)
            (- wave-interval (remainder (- tick first-wave) wave-interval)))))

    ;; Wave n sends min(8, n) enemies from each surviving nest, each with
    ;; 30 + 10n health.
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
    (define (spawn world cell health)
      (match (fresh-id world)
        ((Pair id world)
         (World-enemies-set world (Cons (Enemy id (Mover cell cell (Nil)) health (None)) (World-enemies world))))))

    ;; ---- Enemies ----

    ;; An enemy walks to the nearest building by path and strikes it every
    ;; ten ticks once it stands on it; a lost target is replaced.
    (: update-enemies (-> World World))
    (define (update-enemies world)
      (fold-left update-enemy world (World-enemies world)))

    (: update-enemy (-> World Enemy World))
    (define (update-enemy world enemy)
      (let* ((enemy (match (target-building world enemy) ((Some _) enemy) ((None) (retarget world enemy))))
             (enemy (Enemy-mover-set enemy (walk world (Enemy-mover enemy) enemy-period))))
        (match (target-building world enemy)
          ((Some target)
           (if (and (arrived? (Enemy-mover enemy)) (cell=? (Mover-cell (Enemy-mover enemy)) (Building-cell target)) (on-period? world 10))
               (put-building (put-enemy world enemy) (Building-health-set target (- (Building-health target) 6)))
               (put-enemy world enemy)))
          ((None) (put-enemy world enemy)))))

    (: target-building (-> World Enemy (Option Building)))
    (define (target-building world enemy)
      (match (Enemy-target enemy)
        ((Some id) (building world id))
        ((None) (None))))

    ;; One search finds both the nearest building and the way to it.
    (: retarget (-> World Enemy Enemy))
    (define (retarget world enemy)
      (let ((start (Mover-cell (Enemy-mover enemy))))
        (match (route world start (lambda (cell) (any? (lambda (b) (cell=? (Building-cell b) cell)) (World-buildings world))))
          ((Some path)
           (let ((goal (match (reverse path) ((Cons last _) last) ((Nil) start))))
             (Enemy-target-set (Enemy-mover-set enemy (Mover-path-set (Enemy-mover enemy) path))
                               (match (find (lambda (b) (cell=? (Building-cell b) goal)) (World-buildings world))
                                 ((Some b) (Some (Building-id b)))
                                 ((None) (None))))))
          ((None) (Enemy-target-set enemy (None))))))

    ;; ---- Guns ----

    ;; Every eight ticks a built gun hits the nearest enemy within six cells
    ;; for 25, or else a nest within six cells.
    (: fire-guns (-> World World))
    (define (fire-guns world)
      (if (on-period? world 8)
          (fold-left fire world (filter (lambda (b) (and (match (Building-kind b) ((Gun) #t) (_ #f))
                                                         (match (Building-stage b) ((Built) #t) ((Site) #f))))
                                        (World-buildings world)))
          world))

    (: fire (-> World Building World))
    (define (fire world gun)
      (let ((cell (Building-cell gun)) (in-range? (lambda (target) (<= (distance-squared (Building-cell gun) target) 36))))
        (match (nearest (filter (lambda (e) (in-range? (Mover-cell (Enemy-mover e)))) (World-enemies world))
                        (lambda (e) (distance-squared cell (Mover-cell (Enemy-mover e)))))
          ((Some enemy)
           (shoot (put-enemy world (Enemy-health-set enemy (- (Enemy-health enemy) 25))) cell (Mover-cell (Enemy-mover enemy))))
          ((None)
           (match (find (lambda (n) (in-range? (Nest-cell n))) (World-nests world))
             ((Some nest)
              (shoot (structures-changed
                      (World-nests-set world (map (lambda (n) (if (= (Nest-id n) (Nest-id nest)) (Nest-health-set n (- (Nest-health n) 25)) n))
                                                  (World-nests world))))
                     cell (Nest-cell nest)))
             ((None) world))))))

    (: shoot (-> World Cell Cell World))
    (define (shoot world from to)
      (World-shots-set world (Cons (Shot from to (+ (World-tick world) 4)) (World-shots world))))

    (: nearest (All (A) (-> (List A) (-> A I64) (Option A))))
    (define (nearest items distance)
      (fold-left (lambda (best item)
                   (match best
                     ((Some other) (if (< (distance item) (distance other)) (Some item) best))
                     ((None) (Some item))))
                 (None) items))

    ;; ---- Ticks ----

    ;; Removes what was destroyed and expired.
    (: clean-up (-> World World))
    (define (clean-up world)
      (let* ((buildings (filter (lambda (b) (> (Building-health b) 0)) (World-buildings world)))
             (nests (filter (lambda (n) (> (Nest-health n) 0)) (World-nests world)))
             (world (World-shots-set (World-enemies-set world (filter (lambda (e) (> (Enemy-health e) 0)) (World-enemies world)))
                                     (filter (lambda (s) (> (Shot-until s) (World-tick world))) (World-shots world)))))
        (if (and (= (length buildings) (length (World-buildings world))) (= (length nests) (length (World-nests world))))
            world
            (structures-changed (World-nests-set (World-buildings-set world buildings) nests)))))

    ;; Losing the hub loses, even on the tick the last nest falls.
    (: judge (-> World World))
    (define (judge world)
      (cond ((not (any? (lambda (b) (match (Building-kind b) ((Hub) #t) (_ #f))) (World-buildings world)))
             (World-message-set (World-outcome-set world (Lost)) "The hub has fallen."))
            ((null? (World-nests world)) (World-message-set (World-outcome-set world (Won)) "Every nest is destroyed. Victory!"))
            (else world)))

    ;; Mining comes first so workers see this tick's stock; damage is removed
    ;; only at the end, so everything alive at the start of a tick acts.
    (: advance (-> World World))
    (define (advance world)
      (match (World-outcome world)
        ((Playing)
         (judge (clean-up (fire-guns (update-enemies (spawn-waves (update-workers (mine (World-tick-set world (+ (World-tick world) 1))))))))))
        (_ world)))

    ;; ---- Orders ----

    ;; Places a site for `kind` at `cell`, paying its cost now.
    (: place (-> World Kind Cell (Result World String)))
    (define (place world kind cell)
      (cond ((not (in-bounds? cell)) (Err "Outside the map."))
            ((not (vector-ref (World-explored world) (cell-index cell))) (Err "That ground is unexplored."))
            ((match (ground-at (World-land world) cell) ((Grass) #f) (_ #t)) (Err "Only grass can be built on."))
            ((any? (lambda (b) (cell=? (Building-cell b) cell)) (World-buildings world)) (Err "Something is already built there."))
            ((match kind ((Extractor) (match (deposit-at world cell) ((None) #t) (_ #f))) (_ #f))
             (Err "Extractors go on ore deposits."))
            ((< (World-ore world) (kind-cost kind)) (Err "Not enough ore."))
            (else (Ok (order-site world kind cell)))))

    (: order-site (-> World Kind Cell World))
    (define (order-site world kind cell)
      (match (fresh-id world)
        ((Pair id world)
         (structures-changed
          (World-message-set
           (World-ore-set (World-buildings-set world (append (World-buildings world) (list (Building id kind (Site) cell (kind-health kind) 0))))
                          (- (World-ore world) (kind-cost kind)))
           (string-append (kind-name kind) " ordered."))))))

    (: recruit (-> World (Result World String)))
    (define (recruit world)
      (if (< (World-ore world) 40)
          (Err "A worker costs 40 ore.")
          (match (fresh-id world)
            ((Pair id world)
             (Ok (World-message-set
                  (World-ore-set (World-workers-set world (append (World-workers world) (list (Worker id (Mover (world-hub world) (world-hub world) (Nil)) 0 (Idle)))))
                                 (- (World-ore world) 40))
                  "A new worker joins the colony."))))))

    ))
