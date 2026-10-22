;; The colony's state: the land, the hub, buildings and their work, workers,
;; crystals, nests and enemies, and what derives from them: the wires
;; between buildings, which buildings are powered, which cells they light,
;; and the walls that stand as terrain.
;;
;; Recorded state changes only through `act` and `advance`. Derived state
;; (the network, sight and the wall map) is recomputed by `rewire` from the
;; recorded state whenever a building is finished or removed, so it is
;; never stale.
;;
;; Ids only increase, so the oldest thing has the smallest id. Buildings
;; and workers share one count. The hub is node 0 of the network.
(define-library (siegework world)
  (export
   Kind
   Extractor
   Pylon
   Turret
   Wall
   kind-name
   kind-health
   kind-reach
   has-kind?
   maximum-level
   raise-cost
   raise-duration
   portal-cost
   portal-duration
   Labor
   Raising
   Linking
   Mending
   Training
   needs-worker?
   Work
   Work-order
   Work-labor
   Work-cost
   Work-duration
   Work-progress
   Work-progress-set
   remaining-work
   rush-price
   work-refund
   Building
   Building-id
   Building-kind
   Building-cell
   Building-level
   Building-level-set
   Building-health
   Building-health-set
   Building-work
   Building-aim
   Building-aim-set
   Building-work-set
   Building-portal
   Building-portal-set
   built?
   wall?
   portal?
   full-health
   building-reach
   invested
   Hub
   Hub-cell
   Hub-health
   Hub-health-set
   Hub-work
   Hub-work-set
   Hub-training
   Hub-training-set
   hub-health
   hub-reach
   hub-cell?
   hub-cells
   Worker
   Worker-id
   Worker-cell
   Worker-cell-set
   Worker-previous
   Worker-previous-set
   Worker-health
   Worker-health-set
   Worker-job
   Worker-job-set
   worker-cost
   worker-duration
   worker-health
   worker-damage
   worker-period
   maximum-workers
   starting-workers
   add-worker
   Crystal
   Crystal-cell
   Crystal-rate
   Crystal-reserve
   Crystal-reserve-set
   Nest
   Nest-front
   Nest-cell
   Nest-health
   Nest-health-set
   nest-health
   Behavior
   Minion
   Raider
   Beast
   Enemy
   Enemy-id
   Enemy-behavior
   Enemy-rank
   Enemy-burrower
   Enemy-aggression
   Enemy-cell
   Enemy-cell-set
   Enemy-previous
   Enemy-previous-set
   Enemy-health
   Enemy-health-set
   Enemy-maximum
   Enemy-sighted
   Enemy-sighted-set
   Enemy-target
   Enemy-target-set
   Enemy-plan
   Enemy-plan-set
   Plan
   Plan-goal
   Plan-terrain
   Plan-digging
   Dig
   Dig-cell
   Dig-remaining
   rock-health
   Alert
   Alert-cell
   Alert-tick
   Route
   Route-goal
   Route-key
   Route-field
   portal-key
   Shot
   Shot-from
   Shot-to
   Shot-tick
   Outcome
   Playing
   Won
   Lost
   Resigned
   Ledger
   Ledger-produced
   Ledger-spent
   Ledger-kills
   Ledger-kills-set
   Ledger-lost
   Ledger-lost-set
   Node
   Node-id
   Node-kind
   Node-cell
   Node-reach
   Wire
   Wire-from
   Wire-to
   Network
   Network-wires
   Network-powered
   Reveal
   Reveal-before
   Reveal-center
   Reveal-radius
   Reveal-tick
   World
   World-seed
   World-land
   World-tick
   World-tick-set
   World-started
   World-started-set
   World-outcome
   World-outcome-set
   World-energy
   World-hub
   World-hub-set
   World-buildings
   World-buildings-set
   World-workers
   World-workers-set
   World-crystals
   World-nests
   World-nests-set
   World-enemies
   World-enemies-set
   World-shots
   World-shots-set
   World-digs
   World-opened
   World-digs-set
   World-alerts
   World-alerts-set
   World-routes
   World-routes-set
   World-terrain
   World-walls
   World-ledger
   World-ledger-set
   World-next-order
   World-next-order-set
   World-network
   World-visible
   World-explored
   World-reveal
   World-structure-version
   World-explored-version
   starting-energy
   new-world
   playing?
   fresh-id
   building
   building-at
   put-building
   remove-building
   worker
   put-worker
   crystal-at
   put-crystal
   nest-at
   opened?
   walled?
   enemy-beside?
   open-rock
   spend
   earn
   structures-changed
   powered?
   wire-reaches?
   joinable?
   clear-line?
   clear-shot?
   rewire
   uncover
   lit-cells
   visible?
   explored?)
  (import
   (lofi base)
   (lofi wire)
   (siegework grid)
   (siegework terrain))
  (begin

    ;; ---- Buildings ----

    ;; Extractors drain crystals into the network's energy, pylons extend it
    ;; and see far, turrets shoot enemies and nests, and walls stand as
    ;; terrain that enemies must dig through.
    (enum Kind
      (Extractor)
      (Pylon)
      (Turret)
      (Wall)
      (deriving Serialize Deserialize))

    ;; What a work does when it is done: raise its owner one level, make a
    ;; pylon a portal, restore the hub to full health, or train a worker.
    ;; Every labor but training needs a worker at the site.
    (enum Labor
      (Raising)
      (Linking)
      (Mending)
      (Training))

    ;; Work raises its owner one level, or does its other labor. Its cost
    ;; and duration are fixed when it is ordered. Progress grows by one each
    ;; tick a worker labors at the site while its owner is powered; a worker
    ;; is trained at the hub without one.
    (struct Work
      ((order I64)
       (labor Labor)
       (cost I64)
       (duration I64)
       (progress I64)))

    ;; A building at level 0 is an unfinished site: it neither carries wires
    ;; nor works, but enemies may still destroy it. `aim` is where a turret
    ;; last fired; its guns stay there until it fires again. A pylon may
    ;; also be a portal.
    (struct Building
      ((id I64)
       (kind Kind)
       (cell Cell)
       (level I64)
       (health I64)
       (work (Option Work))
       (aim (Option Cell))
       (portal Bool)))

    (: kind-name (-> Kind String))
    (define (kind-name kind)
      (match kind
        ((Extractor) "Extractor")
        ((Pylon) "Pylon")
        ((Turret) "Turret")
        ((Wall) "Wall")))

    ;; A building's full health at `level`; only walls grow sturdier.
    (: kind-health (-> Kind I64 I64))
    (define (kind-health kind level)
      (match kind
        ((Extractor) 140)
        ((Pylon) 90)
        ((Turret) 100)
        ((Wall) (case level ((2) 250) ((3) 300) (else 200)))))

    ;; How far a powered building of `kind` at `level` sees, and the longest
    ;; wire it can hold.
    (: kind-reach (-> Kind I64 I64))
    (define (kind-reach kind level)
      (match kind
        ((Extractor) 4)
        ((Pylon) (case level ((1) 7) ((2) 10) (else 12)))
        ;; Turrets neither see nor hold wires: they shoot only what other
        ;; buildings reveal, and draw power only inside a pylon's reach.
        ((Turret) 0)
        ;; Walls pass power only to what touches or sees them.
        ((Wall) 0)))

    (: kind-index (-> Kind I64))
    (define (kind-index kind)
      (match kind
        ((Extractor) 0)
        ((Pylon) 1)
        ((Turret) 2)
        ((Wall) 3)))

    ;; Whether an optional kind (the hub has none) is `kind`.
    (: has-kind? (-> (Option Kind) Kind Bool))
    (define (has-kind? option kind)
      (match option
        ((Some k) (= (kind-index k) (kind-index kind)))
        ((None) #f)))

    (: maximum-level I64)
    (define maximum-level 3)

    ;; The energy and ticks of work that raise a `kind` from `level`.
    (: raise-cost (-> Kind I64 I64))
    (define (raise-cost kind level)
      (match kind
        ((Extractor) (case level ((0) 25) ((1) 40) (else 160)))
        ((Pylon) (case level ((0) 25) ((1) 25) (else 50)))
        ((Turret) (case level ((0) 50) (else 25)))
        ((Wall) (case level ((0) 10) ((1) 10) (else 15)))))

    (: raise-duration (-> Kind I64 I64))
    (define (raise-duration kind level)
      (match kind
        ((Extractor) (case level ((0) 30) ((1) 40) (else 60)))
        ((Pylon) (case level ((0) 20) ((1) 30) (else 50)))
        ((Turret) (case level ((0) 40) ((1) 40) (else 60)))
        ((Wall) 20)))

    ;; Making a built pylon a portal, at any level.
    (: portal-cost I64)
    (define portal-cost 60)

    (: portal-duration I64)
    (define portal-duration 40)

    (: needs-worker? (-> Labor Bool))
    (define (needs-worker? labor)
      (match labor
        ((Training) #f)
        (_ #t)))

    (: built? (-> Building Bool))
    (define (built? building)
      (> (Building-level building) 0))

    (: wall? (-> Building Bool))
    (define (wall? building)
      (match (Building-kind building)
        ((Wall) #t)
        (_ #f)))

    ;; A portal works only while it is built and powered.
    (: portal? (-> Building Bool))
    (define (portal? building)
      (and (built? building) (Building-portal building)))

    (: full-health (-> Building I64))
    (define (full-health building)
      (kind-health (Building-kind building) (max 1 (Building-level building))))

    (: building-reach (-> Building I64))
    (define (building-reach building)
      (kind-reach (Building-kind building) (max 1 (Building-level building))))

    ;; Everything paid for the levels a building has reached, and for its
    ;; portal.
    (: invested (-> Building I64))
    (define (invested building)
      (+ (fold-left + 0 (map (lambda (level) (raise-cost (Building-kind building) level)) (iota (Building-level building))))
         (if (Building-portal building) portal-cost 0)))

    ;; ---- Work ----

    (: remaining-work (-> Work I64))
    (define (remaining-work work)
      (max 0 (- (Work-duration work) (Work-progress work))))

    ;; Rushing finishes the work at once for four times the share of its
    ;; cost that remains, rounded up, so rushing as it is ordered costs five
    ;; times the price in all, and rushing later costs less.
    (: rush-price (-> Work I64))
    (define (rush-price work)
      (quotient (+ (* 4 (* (Work-cost work) (remaining-work work))) (- (Work-duration work) 1)) (Work-duration work)))

    ;; Cancelling returns the whole cost.
    (: work-refund (-> Work I64))
    (define (work-refund work)
      (Work-cost work))

    ;; ---- The hub ----

    ;; The hub covers the three by three cells around its center. Its work
    ;; is a repair; `training` holds the workers ordered, oldest first, of
    ;; which the first is being trained.
    (struct Hub
      ((cell Cell)
       (health I64)
       (work (Option Work))
       (training (List Work))))

    (: hub-health I64)
    (define hub-health 600)

    (: hub-reach I64)
    (define hub-reach 9)

    (: hub-cell? (-> Hub Cell Bool))
    (define (hub-cell? hub cell)
      (and (<= (abs (- (Cell-x cell) (Cell-x (Hub-cell hub)))) 1) (<= (abs (- (Cell-y cell) (Cell-y (Hub-cell hub)))) 1)))

    ;; The hub's footprint, row by row.
    (: hub-cells (-> Hub (List Cell)))
    (define (hub-cells hub)
      (let ((center (Hub-cell hub)))
        (filter in-bounds? (map (lambda (i) (Cell (+ (Cell-x center) (- (remainder i 3) 1)) (+ (Cell-y center) (- (quotient i 3) 1)))) (iota 9)))))

    ;; ---- Workers ----

    ;; Workers walk to the colony's work and labor there; they cannot dig.
    ;; `job` is the id of the owner whose work it took: a building, or 0
    ;; for the hub. A worker steps from `previous` to `cell` on multiples of
    ;; its period.
    (struct Worker
      ((id I64)
       (cell Cell)
       (previous Cell)
       (health I64)
       (job (Option I64))))

    (: worker-cost I64)
    (define worker-cost 20)

    (: worker-duration I64)
    (define worker-duration 30)

    (: worker-health I64)
    (define worker-health 60)

    ;; A worker strikes an enemy beside it once a second for this much.
    (: worker-damage I64)
    (define worker-damage 6)

    (: worker-period I64)
    (define worker-period 5)

    (: maximum-workers I64)
    (define maximum-workers 20)

    (: starting-workers I64)
    (define starting-workers 3)

    ;; A new worker stands at the hub's center.
    (: add-worker (-> World World))
    (define (add-worker world)
      (match (fresh-id world)
        ((Pair id world)
         (let ((cell (Hub-cell (World-hub world))))
           (World-workers-set world (append (World-workers world) (list (Worker id cell cell worker-health (None)))))))))

    ;; ---- Crystals and nests ----

    (struct Crystal
      ((cell Cell)
       (rate I64)
       (reserve I64)))

    ;; Each nest covers a rich crystal, exposed when the nest is destroyed.
    (struct Nest
      ((front I64)
       (cell Cell)
       (health I64)))

    (: nest-health I64)
    (define nest-health 900)

    ;; ---- Enemies ----

    ;; Minions make up attacks, raiders the raids, and a beast leads each
    ;; heavy attack.
    (enum Behavior
      (Minion)
      (Raider)
      (Beast))

    ;; An enemy steps from `previous` to `cell` on multiples of its period.
    ;; Its rank, from 0 to 6, sets its health and the damage it strikes and
    ;; digs for; `maximum` is its health when it spawned. A burrower digs
    ;; three times as fast. `aggression` is the percent chance it attacks a
    ;; structure or worker that comes into its sight; `sighted` holds the
    ;; ids it has already rolled for, so each is rolled for once. `target`
    ;; is the id of the structure or worker it is attacking, the nearest in
    ;; sight; with none it heads for the hub.
    (struct Enemy
      ((id I64)
       (behavior Behavior)
       (rank I64)
       (burrower Bool)
       (aggression I64)
       (cell Cell)
       (previous Cell)
       (health I64)
       (maximum I64)
       (sighted (List I64))
       (target (Option I64))
       (plan Plan)))

    ;; The route an enemy last planned: toward `goal`, the id of what it
    ;; attacks or 0 for the hub, on the terrain of version `terrain`, and
    ;; whether it chose to dig. It plans again when either changes.
    (struct Plan
      ((goal I64)
       (terrain I64)
       (digging Bool)))

    ;; Rock being dug, with what remains of it.
    (struct Dig
      ((cell Cell)
       (remaining I64)))

    (: rock-health I64)
    (define rock-health 300)

    ;; A shot is drawn for a few ticks after a turret fires.
    (struct Shot
      ((from Cell)
       (to Cell)
       (tick I64)))

    ;; Where the colony was last struck, and when.
    (struct Alert
      ((cell Cell)
       (tick I64)))

    ;; A cost field toward `goal` for one kind of mover, named by `key`,
    ;; kept until the terrain changes. The field toward the portals is
    ;; kept only until the network changes.
    (struct Route
      ((goal Cell)
       (key I64)
       (field Field)))

    (: portal-key I64)
    (define portal-key -1)

    ;; ---- Outcome and ledger ----

    (enum Outcome
      (Playing)
      (Won)
      (Lost)
      (Resigned))

    ;; Energy produced and spent, net of refunds, so energy is always
    ;; starting-energy + produced - spent; and the colony's losses.
    (struct Ledger
      ((produced I64)
       (spent I64)
       (kills I64)
       (lost I64)))

    ;; ---- Network ----

    ;; A node is the hub (id 0, no kind) or a finished building, with its
    ;; reach.
    (struct Node
      ((id I64)
       (kind (Option Kind))
       (cell Cell)
       (reach I64)))

    (struct Wire
      ((from Node)
       (to Node)))

    ;; The wires, each from the node it was reached from to the next, and
    ;; the nodes the hub reaches through them, in the order reached.
    (struct Network
      ((wires (List Wire))
       (powered (List Node))))

    ;; The cells explored most recently, for drawing them unveiled: those
    ;; explored now but not `before`, within `radius` of `center`, since
    ;; `tick`.
    (struct Reveal
      ((before (Vector Bool))
       (center Cell)
       (radius I64)
       (tick I64)))

    ;; ---- World ----

    ;; The versions change whenever the buildings or the explored cells do,
    ;; so a view can reuse what it drew. `terrain` counts changes to what
    ;; movers cross: rock opened and walls raised or lost. `walls` holds
    ;; each standing wall's full health at its cell, and 0 elsewhere.
    (struct World
      ((seed I64)
       (land Land)
       (tick I64)
       (started Bool)
       (outcome Outcome)
       (energy I64)
       (hub Hub)
       (buildings (List Building))
       (workers (List Worker))
       (crystals (List Crystal))
       (nests (List Nest))
       (enemies (List Enemy))
       (digs (List Dig))
       (opened (Vector Bool))
       (shots (List Shot))
       (alerts (List Alert))
       (routes (List Route))
       (terrain I64)
       (walls (Vector I64))
       (ledger Ledger)
       (next-id I64)
       (next-order I64)
       (network Network)
       (visible (Vector Bool))
       (explored (Vector Bool))
       (reveal Reveal)
       (structure-version I64)
       (explored-version I64)))

    (: starting-energy I64)
    (define starting-energy 160)

    ;; Each crystal site holds its full reserve, the nests cover theirs, and
    ;; each front holds a nest. The colony starts with its hub and its first
    ;; workers, the ground around it already unveiled.
    (: new-world (-> I64 World))
    (define (new-world seed)
      (let ((world (first-world seed)))
        (World-reveal-set world (Reveal-tick-set (World-reveal world) -1000))))

    (: first-world (-> I64 World))
    (define (first-world seed)
      (let* ((land (new-land (land-seed seed))) (cells (* map-size map-size))
             (world (World seed land 0 #f (Playing) starting-energy (Hub (Land-hub land) hub-health (None) (Nil)) (Nil) (Nil)
                           (append (map site-crystal (Land-sites land)) (map nest-crystal (Land-fronts land)))
                           (map-indexed (lambda (front cell) (Nest front cell nest-health)) (Land-fronts land))
                           (Nil) (Nil) (make-vector cells #f) (Nil) (Nil) (Nil) 0 (make-vector cells 0) (Ledger 0 0 0 0) 1 1 (Network (Nil) (Nil))
                           (make-vector cells #f) (make-vector cells #f) (Reveal (make-vector cells #f) (Land-hub land) 0 0) 0 0)))
        (rewire (fold-left (lambda (world index) (add-worker world)) world (iota starting-workers)))))

    (: site-crystal (-> Site Crystal))
    (define (site-crystal site)
      (Crystal (Site-cell site) (Site-rate site) (* reserve-per-rate (Site-rate site))))

    (: nest-crystal (-> Cell Crystal))
    (define (nest-crystal cell)
      (Crystal cell nest-rate (* reserve-per-rate nest-rate)))

    (: playing? (-> World Bool))
    (define (playing? world)
      (match (World-outcome world)
        ((Playing) #t)
        (_ #f)))

    (: fresh-id (-> World (Pair I64 World)))
    (define (fresh-id world)
      (Pair (World-next-id world) (World-next-id-set world (+ (World-next-id world) 1))))

    ;; ---- Lookups and replacements ----

    (: building (-> World I64 (Option Building)))
    (define (building world id)
      (find (lambda (b) (= (Building-id b) id)) (World-buildings world)))

    (: building-at (-> World Cell (Option Building)))
    (define (building-at world cell)
      (find (lambda (b) (cell=? (Building-cell b) cell)) (World-buildings world)))

    (: put-building (-> World Building World))
    (define (put-building world building)
      (World-buildings-set world (map (lambda (b) (if (= (Building-id b) (Building-id building)) building b)) (World-buildings world))))

    (: remove-building (-> World I64 World))
    (define (remove-building world id)
      (rewire (World-buildings-set world (filter (lambda (b) (not (= (Building-id b) id))) (World-buildings world)))))

    (: worker (-> World I64 (Option Worker)))
    (define (worker world id)
      (find (lambda (w) (= (Worker-id w) id)) (World-workers world)))

    (: put-worker (-> World Worker World))
    (define (put-worker world worker)
      (World-workers-set world (map (lambda (w) (if (= (Worker-id w) (Worker-id worker)) worker w)) (World-workers world))))

    (: crystal-at (-> World Cell (Option Crystal)))
    (define (crystal-at world cell)
      (find (lambda (crystal) (cell=? (Crystal-cell crystal) cell)) (World-crystals world)))

    (: put-crystal (-> World Crystal World))
    (define (put-crystal world crystal)
      (World-crystals-set world (map (lambda (c) (if (cell=? (Crystal-cell c) (Crystal-cell crystal)) crystal c)) (World-crystals world))))

    (: nest-at (-> World Cell (Option Nest)))
    (define (nest-at world cell)
      (find (lambda (nest) (cell=? (Nest-cell nest) cell)) (World-nests world)))

    ;; Rock that enemies have dug through for good.
    (: opened? (-> World Cell Bool))
    (define (opened? world cell)
      (vector-ref (World-opened world) (cell-index cell)))

    ;; Whether a finished wall stands on the cell.
    (: walled? (-> World Cell Bool))
    (define (walled? world cell)
      (> (vector-ref (World-walls world) (cell-index cell)) 0))

    ;; Whether an enemy stands on the cell or beside it.
    (: enemy-beside? (-> World Cell Bool))
    (define (enemy-beside? world cell)
      (any? (lambda (e) (beside? (Enemy-cell e) cell)) (World-enemies world)))

    ;; Opening rock changes the terrain and may clear wires and shots.
    (: open-rock (-> World Cell World))
    (define (open-rock world cell)
      (rewire (terrain-changed (World-opened-set world (vector-set (World-opened world) (cell-index cell) #t)))))

    ;; Every route crosses the old terrain, so all are dropped, and every
    ;; enemy plans again.
    (: terrain-changed (-> World World))
    (define (terrain-changed world)
      (World-terrain-set (World-routes-set world (Nil)) (+ (World-terrain world) 1)))

    ;; Spending and earning keep energy and the ledger in step; a refund is
    ;; negative spending.
    (: spend (-> World I64 World))
    (define (spend world amount)
      (World-ledger-set (World-energy-set world (- (World-energy world) amount))
                        (Ledger-spent-set (World-ledger world) (+ (Ledger-spent (World-ledger world)) amount))))

    (: earn (-> World I64 World))
    (define (earn world amount)
      (World-ledger-set (World-energy-set world (+ (World-energy world) amount))
                        (Ledger-produced-set (World-ledger world) (+ (Ledger-produced (World-ledger world)) amount))))

    (: structures-changed (-> World World))
    (define (structures-changed world)
      (World-structure-version-set world (+ (World-structure-version world) 1)))

    ;; ---- Wires and power ----

    ;; Wires and sight lines cross everything but intact rock.
    (: clear-line? (-> World Cell Cell Bool))
    (define (clear-line? world from to)
      (every? (lambda (cell) (match (ground-at (World-land world) cell) ((Rock) (opened? world cell)) (_ #t))) (line-cells from to)))

    ;; Shots stop at walls as well as rock.
    (: clear-shot? (-> World Cell Cell Bool))
    (define (clear-shot? world from to)
      (and (clear-line? world from to) (not (any? (lambda (cell) (walled? world cell)) (line-cells from to)))))

    ;; A wire reaches as far as the longer reach of its two ends.
    (: wire-reaches? (-> World Cell I64 Cell I64 Bool))
    (define (wire-reaches? world a reach-a b reach-b)
      (and (within? a b (max reach-a reach-b)) (clear-line? world a b)))

    ;; Turrets draw power only from pylons: a wire with a turret at one end
    ;; needs a pylon at the other. Walls pass power to each other and to
    ;; pylons or the hub, never to anything else. The hub has no kind.
    (: joinable? (-> (Option Kind) (Option Kind) Bool))
    (define (joinable? a b)
      (cond ((has-kind? a (Wall)) (or (has-kind? b (Wall)) (carrier? b)))
            ((has-kind? b (Wall)) (carrier? a))
            (else (and (or (not (has-kind? a (Turret))) (has-kind? b (Pylon)))
                       (or (not (has-kind? b (Turret))) (has-kind? a (Pylon)))))))

    ;; The hub and pylons carry power from walls.
    (: carrier? (-> (Option Kind) Bool))
    (define (carrier? kind)
      (match kind
        ((Some _) (has-kind? kind (Pylon)))
        ((None) #t)))

    (: hub-node (-> World Node))
    (define (hub-node world)
      (Node 0 (None) (Hub-cell (World-hub world)) hub-reach))

    (: building-nodes (-> World (List Node)))
    (define (building-nodes world)
      (map (lambda (b) (Node (Building-id b) (Some (Building-kind b)) (Building-cell b) (building-reach b))) (filter built? (World-buildings world))))

    ;; A pair of nodes a wire could join, by their places in the list of
    ;; nodes, with the squared length that ranks it.
    (struct Link
      ((a I64)
       (b I64)
       (cost I64)))

    ;; Every pair of nodes a wire reaches, each pair once, in node order.
    (: links (-> World (Vector Node) (List Link)))
    (define (links world nodes)
      (concatenate (map (lambda (i)
                          (filter-map (lambda (k) (link world nodes i (+ k (+ i 1)))) (iota (- (vector-length nodes) (+ i 1)))))
                        (iota (vector-length nodes)))))

    (: link (-> World (Vector Node) I64 I64 (Option Link)))
    (define (link world nodes i j)
      (let ((a (vector-ref nodes i)) (b (vector-ref nodes j)))
        (if (and (joinable? (Node-kind a) (Node-kind b)) (spans? world a b))
            (Some (Link i j (distance-squared (Node-cell a) (Node-cell b))))
            (None))))

    ;; Two walls join where they touch, even at a corner; any other pair
    ;; where a wire reaches. A wall's reach is nothing, so a wall joins a
    ;; pylon or the hub that sees it.
    (: spans? (-> World Node Node Bool))
    (define (spans? world a b)
      (if (and (has-kind? (Node-kind a) (Wall)) (has-kind? (Node-kind b) (Wall)))
          (and (<= (abs (- (Cell-x (Node-cell a)) (Cell-x (Node-cell b)))) 1) (<= (abs (- (Cell-y (Node-cell a)) (Cell-y (Node-cell b)))) 1))
          (wire-reaches? world (Node-cell a) (Node-reach a) (Node-cell b) (Node-reach b))))

    ;; The wires run along a minimum spanning forest of the links: a tree
    ;; grown from the hub, always by the shortest link that reaches a new
    ;; node, then a tree for each group of nodes it could not reach. The
    ;; hub's tree is the powered network, so it reaches exactly what the
    ;; links do, and losing a node may rewire it along links not drawn
    ;; before. Each wire runs from the node it was reached from.
    (: span (-> (Vector Node) (List Link) (Pair (List Node) (List Wire))))
    (define (span nodes links)
      (let loop ((inside (make-vector (vector-length nodes) #f)) (wires (Nil)) (powered (None)))
        (match (find (lambda (i) (not (vector-ref inside i))) (iota (vector-length nodes)))
          ((Some root)
           (match (grow nodes links (vector-set inside root #t) wires (list (vector-ref nodes root)))
             ((Pair (Pair inside wires) tree) (loop inside wires (match powered ((None) (Some (reverse tree))) (_ powered))))))
          ((None) (Pair (match powered ((Some tree) tree) ((None) (Nil))) (reverse wires))))))

    ;; Adds the shortest link from the tree to a new node until none is left.
    (: grow (-> (Vector Node) (List Link) (Vector Bool) (List Wire) (List Node) (Pair (Pair (Vector Bool) (List Wire)) (List Node))))
    (define (grow nodes links inside wires tree)
      (match (shortest-crossing links inside)
        ((Some l) (let* ((outward (vector-ref inside (Link-a l))) (from (if outward (Link-a l) (Link-b l))) (to (if outward (Link-b l) (Link-a l))))
                    (grow nodes links (vector-set inside to #t) (Cons (Wire (vector-ref nodes from) (vector-ref nodes to)) wires) (Cons (vector-ref nodes to) tree))))
        ((None) (Pair (Pair inside wires) tree))))

    ;; The first of the shortest links with one end inside, so ties go to
    ;; the older pair.
    (: shortest-crossing (-> (List Link) (Vector Bool) (Option Link)))
    (define (shortest-crossing links inside)
      (fold-left (lambda (best l)
                   (if (and (not (eq-bool? (vector-ref inside (Link-a l)) (vector-ref inside (Link-b l))))
                            (match best ((Some b) (< (Link-cost l) (Link-cost b))) ((None) #t)))
                       (Some l)
                       best))
                 (None) links))

    (: eq-bool? (-> Bool Bool Bool))
    (define (eq-bool? a b)
      (if a b (not b)))

    (: filter-map (All (A B) (-> (-> A (Option B)) (List A) (List B))))
    (define (filter-map f items)
      (fold-right (lambda (item kept) (match (f item) ((Some value) (Cons value kept)) ((None) kept))) (Nil) items))

    (: powered? (-> World I64 Bool))
    (define (powered? world id)
      (any? (lambda (node) (= (Node-id node) id)) (Network-powered (World-network world))))

    ;; ---- Sight ----

    ;; Every cell within reach of one of `nodes`.
    (: lit-cells (-> (List Node) (Vector Bool)))
    (define (lit-cells nodes)
      (unsafe-total
       (lambda ()
         (let ((seen (make-array (* map-size map-size) #f)))
           (for-each (lambda (node) (light! seen (Node-cell node) (Node-reach node))) nodes)
           (array->vector seen)))))

    (: light! (-> (Array Bool) Cell I64 Unit ! mut))
    (define (light! seen center radius)
      (let ((offsets (map (lambda (i) (- i radius)) (iota (+ 1 (* 2 radius))))))
        (for-each (lambda (dy)
                    (for-each (lambda (dx)
                                (let ((cell (Cell (+ (Cell-x center) dx) (+ (Cell-y center) dy))))
                                  (when (and (in-bounds? cell) (within? cell center radius))
                                    (array-set! seen (cell-index cell) #t))))
                              offsets))
                  offsets)))

    (: visible? (-> World Cell Bool))
    (define (visible? world cell)
      (vector-ref (World-visible world) (cell-index cell)))

    (: explored? (-> World Cell Bool))
    (define (explored? world cell)
      (vector-ref (World-explored world) (cell-index cell)))

    ;; ---- Walls as terrain ----

    ;; Each finished wall's full health at its cell. The array is local to
    ;; the call, so it is total.
    (: wall-map (-> World (Vector I64)))
    (define (wall-map world)
      (unsafe-total
       (lambda ()
         (let ((cells (make-array (* map-size map-size) 0)))
           (for-each (lambda (b) (when (and (built? b) (wall? b)) (array-set! cells (cell-index (Building-cell b)) (full-health b))))
                     (World-buildings world))
           (array->vector cells)))))

    (: same-numbers? (-> (Vector I64) (Vector I64) Bool))
    (define (same-numbers? a b)
      (let loop ((index 0))
        (cond ((= index (vector-length a)) #t)
              ((= (vector-ref a index) (vector-ref b index)) (loop (+ index 1)))
              (else #f))))

    ;; A wall raised, upgraded or lost changes the terrain.
    (: rebuild-walls (-> World World))
    (define (rebuild-walls world)
      (let ((walls (wall-map world)))
        (if (same-numbers? walls (World-walls world)) world (terrain-changed (World-walls-set world walls)))))

    ;; ---- Rewiring ----

    ;; Recomputes the walls, wires, power and sight after the buildings
    ;; change, and forgets the way to the portals, which may have gained or
    ;; lost power. A cell once visible stays explored.
    (: rewire (-> World World))
    (define (rewire world)
      (let* ((world (rebuild-walls world))
             (world (World-routes-set world (filter (lambda (route) (not (= (Route-key route) portal-key))) (World-routes world))))
             (nodes (list->vector (Cons (hub-node world) (building-nodes world)))) (spanned (span nodes (links world nodes))))
        (explore (structures-changed (World-visible-set (World-network-set world (Network (Pair-second spanned) (Pair-first spanned)))
                                                        (lit-cells (Pair-first spanned)))))))

    (: explore (-> World World))
    (define (explore world)
      (let* ((explored (World-explored world)) (visible (World-visible world))
             (fresh (filter (lambda (index) (and (vector-ref visible index) (not (vector-ref explored index)))) (iota (vector-length visible)))))
        (if (null? fresh)
            world
            (World-explored-version-set
             (World-reveal-set (World-explored-set world (vector-generate (vector-length visible) (lambda (index) (or (vector-ref explored index) (vector-ref visible index)))))
                               (reveal-around explored (map index-cell fresh) (World-tick world)))
             (+ (World-explored-version world) 1)))))

    ;; The newly explored cells unveil from their middle outward.
    (: reveal-around (-> (Vector Bool) (List Cell) I64 Reveal))
    (define (reveal-around before cells tick)
      (let* ((count (length cells))
             (center (Cell (quotient (fold-left + 0 (map Cell-x cells)) count) (quotient (fold-left + 0 (map Cell-y cells)) count))))
        (Reveal before center (+ 1 (integer-sqrt (fold-left max 0 (map (lambda (cell) (distance-squared cell center)) cells)))) tick)))

    ;; A decided game shows the whole map for inspection, at once: the world
    ;; is still, so nothing could unveil.
    (: uncover (-> World World))
    (define (uncover world)
      (let ((everything (make-vector (* map-size map-size) #t)) (reveal (World-reveal world)))
        (structures-changed (World-explored-version-set (World-reveal-set (World-visible-set (World-explored-set world everything) everything)
                                                                          (Reveal-tick-set reveal -1000))
                                                        (+ (World-explored-version world) 1)))))

    ))
