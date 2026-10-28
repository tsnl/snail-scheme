;; The colony's state: the land, the hub, buildings and their work, crystals,
;; nests and enemies, and what derives from them: the wires between
;; buildings, which buildings are powered and which cells they light.
;;
;; Recorded state changes only through `act` and `advance`. Derived state
;; (the network and sight) is recomputed by `rewire` from the recorded state
;; whenever a building is finished or removed, so it is never stale.
;;
;; Ids only increase, so the oldest thing has the smallest id. The hub is
;; node 0 of the network; buildings count from 1.
(define-library (siegework world)
  (export
   Kind
   Extractor
   Pylon
   Turret
   kind-name
   kind-health
   kind-reach
   maximum-level
   raise-cost
   raise-duration
   Work
   Work-order
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
   built?
   building-reach
   invested
   Hub
   Hub-cell
   Hub-health
   Hub-health-set
   Hub-slots
   Hub-slots-set
   Hub-work
   Hub-work-set
   hub-health
   hub-reach
   maximum-slots
   slot-cost
   slot-duration
   hub-cell?
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
   Enemy-cell
   Enemy-cell-set
   Enemy-previous
   Enemy-previous-set
   Enemy-health
   Enemy-health-set
   Enemy-maximum
   Enemy-raid
   Enemy-aggro
   Enemy-aggro-set
   Dig
   Dig-cell
   Dig-remaining
   rock-health
   Alert
   Alert-cell
   Alert-tick
   Route
   Route-goal
   Route-burrower
   Route-field
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
   opening?
   fresh-id
   building
   building-at
   put-building
   remove-building
   crystal-at
   put-crystal
   nest-at
   opened?
   open-rock
   spend
   earn
   structures-changed
   powered?
   wire-reaches?
   clear-line?
   rewire
   uncover
   lit-cells
   visible?
   explored?)
  (import
   (snail-core base)
   (snail-core wire)
   (siegework grid)
   (siegework terrain))
  (begin

    ;; ---- Buildings ----

    ;; Extractors drain crystals into the network's energy, pylons extend it
    ;; and see far, and turrets shoot enemies and nests.
    (enum Kind
      (Extractor)
      (Pylon)
      (Turret)
      (deriving Serialize Deserialize))

    ;; Work raises its owner one level: a site at level 0 becomes a building,
    ;; a building gains a level and the hub gains a build slot. Its cost and
    ;; duration are fixed when it is ordered. Progress grows by one each tick
    ;; the work holds a hub slot and its owner is powered.
    (struct Work
      ((order I64)
       (cost I64)
       (duration I64)
       (progress I64)))

    ;; A building at level 0 is an unfinished site: it neither carries wires
    ;; nor works, but enemies may still destroy it. `aim` is where a turret
    ;; last fired; its guns stay there until it fires again.
    (struct Building
      ((id I64)
       (kind Kind)
       (cell Cell)
       (level I64)
       (health I64)
       (work (Option Work))
       (aim (Option Cell))))

    (: kind-name (-> Kind String))
    (define (kind-name kind)
      (match kind
        ((Extractor) "Extractor")
        ((Pylon) "Pylon")
        ((Turret) "Turret")))

    (: kind-health (-> Kind I64))
    (define (kind-health kind)
      (match kind
        ((Extractor) 140)
        ((Pylon) 90)
        ((Turret) 100)))

    ;; How far a powered building of `kind` at `level` sees, and the longest
    ;; wire it can hold.
    (: kind-reach (-> Kind I64 I64))
    (define (kind-reach kind level)
      (match kind
        ((Extractor) 4)
        ((Pylon) (case level ((1) 7) ((2) 10) (else 12)))
        ((Turret) 6)))

    (: maximum-level I64)
    (define maximum-level 3)

    ;; The energy and ticks of work that raise a `kind` from `level`.
    (: raise-cost (-> Kind I64 I64))
    (define (raise-cost kind level)
      (match kind
        ((Extractor) (case level ((0) 25) ((1) 40) (else 160)))
        ((Pylon) (case level ((0) 25) ((1) 25) (else 50)))
        ((Turret) (case level ((0) 50) (else 25)))))

    (: raise-duration (-> Kind I64 I64))
    (define (raise-duration kind level)
      (match kind
        ((Extractor) (case level ((0) 30) ((1) 40) (else 60)))
        ((Pylon) (case level ((0) 20) ((1) 30) (else 50)))
        ((Turret) (case level ((0) 40) ((1) 40) (else 60)))))

    (: built? (-> Building Bool))
    (define (built? building)
      (> (Building-level building) 0))

    (: building-reach (-> Building I64))
    (define (building-reach building)
      (kind-reach (Building-kind building) (max 1 (Building-level building))))

    ;; Everything paid for the levels a building has reached.
    (: invested (-> Building I64))
    (define (invested building)
      (fold-left +
                 0
                 (map (lambda (level) (raise-cost (Building-kind building) level))
                      (iota (Building-level building)))))

    ;; ---- Work ----

    (: remaining-work (-> Work I64))
    (define (remaining-work work)
      (max 0 (- (Work-duration work) (Work-progress work))))

    ;; Rushing finishes the work at once for four times the share of its
    ;; cost that remains, rounded up, so rushing as it is ordered costs five
    ;; times the price in all, and rushing later costs less.
    (: rush-price (-> Work I64))
    (define (rush-price work)
      (quotient (+ (* 4 (* (Work-cost work) (remaining-work work))) (- (Work-duration work) 1))
                (Work-duration work)))

    ;; Cancelling returns the whole cost.
    (: work-refund (-> Work I64))
    (define (work-refund work)
      (Work-cost work))

    ;; ---- The hub ----

    ;; The hub covers the three by three cells around its center. Its work
    ;; adds a build slot: the number of works that progress at once.
    (struct Hub
      ((cell Cell)
       (health I64)
       (slots I64)
       (work (Option Work))))

    (: hub-health I64)
    (define hub-health 600)

    (: hub-reach I64)
    (define hub-reach 9)

    (: maximum-slots I64)
    (define maximum-slots 3)

    (: slot-cost (-> I64 I64))
    (define (slot-cost slots)
      (* 100 slots))

    (: slot-duration (-> I64 I64))
    (define (slot-duration slots)
      (+ 20 (* 30 slots)))

    (: hub-cell? (-> Hub Cell Bool))
    (define (hub-cell? hub cell)
      (and (<= (abs (- (Cell-x cell) (Cell-x (Hub-cell hub)))) 1)
           (<= (abs (- (Cell-y cell) (Cell-y (Hub-cell hub)))) 1)))

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

    ;; Minions head for the hub, raiders for an exposed outpost, and a beast
    ;; leads each heavy attack.
    (enum Behavior
      (Minion)
      (Raider)
      (Beast))

    ;; An enemy steps from `previous` to `cell` on multiples of its period.
    ;; Its rank, from 0 to 6, sets its health and the damage it strikes for;
    ;; `maximum` is its health when it spawned. `raid` is the outpost a
    ;; raider chose when it spawned, and `aggro` the turret it turned on when
    ;; hit. Each is kept as an id, which is never reused, so one that no
    ;; longer stands simply names nothing. A burrower digs through rock.
    (struct Enemy
      ((id I64)
       (behavior Behavior)
       (rank I64)
       (burrower Bool)
       (cell Cell)
       (previous Cell)
       (health I64)
       (maximum I64)
       (raid (Option I64))
       (aggro (Option I64))))

    ;; Rock being dug, with what remains of it.
    (struct Dig
      ((cell Cell)
       (remaining I64)))

    (: rock-health I64)
    (define rock-health 80)

    ;; A shot is drawn for a few ticks after a turret fires.
    (struct Shot
      ((from Cell)
       (to Cell)
       (tick I64)))

    ;; Where the colony was last struck, and when.
    (struct Alert
      ((cell Cell)
       (tick I64)))

    ;; A distance field toward a goal for walkers or burrowers, kept until
    ;; rock is opened.
    (struct Route
      ((goal Cell)
       (burrower Bool)
       (field (Vector I64))))

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

    ;; A node is the hub (id 0) or a finished building, with its reach.
    (struct Node
      ((id I64)
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
    ;; so a view can reuse what it drew.
    (struct World
      ((seed I64)
       (land Land)
       (tick I64)
       (started Bool)
       (outcome Outcome)
       (energy I64)
       (hub Hub)
       (buildings (List Building))
       (crystals (List Crystal))
       (nests (List Nest))
       (enemies (List Enemy))
       (digs (List Dig))
       (opened (Vector Bool))
       (shots (List Shot))
       (alerts (List Alert))
       (routes (List Route))
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
    ;; each front holds a nest. The colony starts with its hub alone, the
    ;; ground around it already unveiled.
    (: new-world (-> I64 World))
    (define (new-world seed)
      (let ((world (first-world seed)))
        (World-reveal-set world (Reveal-tick-set (World-reveal world) -1000))))

    (: first-world (-> I64 World))
    (define (first-world seed)
      (let ((land (new-land (land-seed seed))) (cells (* map-size map-size)))
        (rewire (World seed
                       land
                       0
                       #f
                       (Playing)
                       starting-energy
                       (Hub (Land-hub land) hub-health 1 (None))
                       (Nil)
                       (append (map site-crystal (Land-sites land))
                               (map nest-crystal (Land-fronts land)))
                       (map-indexed (lambda (front cell) (Nest front cell nest-health))
                                    (Land-fronts land))
                       (Nil)
                       (Nil)
                       (make-vector cells #f)
                       (Nil)
                       (Nil)
                       (Nil)
                       (Ledger 0 0 0 0)
                       1
                       1
                       (Network (Nil) (Nil))
                       (make-vector cells #f)
                       (make-vector cells #f)
                       (Reveal (make-vector cells #f) (Land-hub land) 0 0)
                       0
                       0))))

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

    ;; The opening: the game is in play, and its first extractor is still
    ;; to be ordered.
    (: opening? (-> World Bool))
    (define (opening? world)
      (and (not (World-started world)) (playing? world)))

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
      (World-buildings-set world
                           (map
                            (lambda (b) (if (= (Building-id b) (Building-id building)) building b))
                            (World-buildings world))))

    (: remove-building (-> World I64 World))
    (define (remove-building world id)
      (rewire (World-buildings-set world
                                   (filter (lambda (b) (not (= (Building-id b) id)))
                                           (World-buildings world)))))

    (: crystal-at (-> World Cell (Option Crystal)))
    (define (crystal-at world cell)
      (find (lambda (crystal) (cell=? (Crystal-cell crystal) cell)) (World-crystals world)))

    (: put-crystal (-> World Crystal World))
    (define (put-crystal world crystal)
      (World-crystals-set world
                          (map (lambda (c)
                                 (if (cell=? (Crystal-cell c) (Crystal-cell crystal)) crystal c))
                               (World-crystals world))))

    (: nest-at (-> World Cell (Option Nest)))
    (define (nest-at world cell)
      (find (lambda (nest) (cell=? (Nest-cell nest) cell)) (World-nests world)))

    ;; Rock that enemies have dug through for good.
    (: opened? (-> World Cell Bool))
    (define (opened? world cell)
      (vector-ref (World-opened world) (cell-index cell)))

    ;; Opening rock changes every route and may clear wires and shots.
    (: open-rock (-> World Cell World))
    (define (open-rock world cell)
      (rewire (World-routes-set
               (World-opened-set world (vector-set (World-opened world) (cell-index cell) #t))
               (Nil))))

    ;; Spending and earning keep energy and the ledger in step; a refund is
    ;; negative spending.
    (: spend (-> World I64 World))
    (define (spend world amount)
      (World-ledger-set (World-energy-set world (- (World-energy world) amount))
                        (Ledger-spent-set (World-ledger world)
                                          (+ (Ledger-spent (World-ledger world)) amount))))

    (: earn (-> World I64 World))
    (define (earn world amount)
      (World-ledger-set (World-energy-set world (+ (World-energy world) amount))
                        (Ledger-produced-set (World-ledger world)
                                             (+ (Ledger-produced (World-ledger world)) amount))))

    (: structures-changed (-> World World))
    (define (structures-changed world)
      (World-structure-version-set world (+ (World-structure-version world) 1)))

    ;; ---- Wires and power ----

    ;; Wires, shots and sight lines cross everything but intact rock.
    (: clear-line? (-> World Cell Cell Bool))
    (define (clear-line? world from to)
      (every? (lambda (cell)
                (match (ground-at (World-land world) cell) ((Rock) (opened? world cell)) (_ #t)))
              (line-cells from to)))

    ;; A wire reaches as far as the longer reach of its two ends.
    (: wire-reaches? (-> World Cell I64 Cell I64 Bool))
    (define (wire-reaches? world a reach-a b reach-b)
      (and (within? a b (max reach-a reach-b)) (clear-line? world a b)))

    (: hub-node (-> World Node))
    (define (hub-node world)
      (Node 0 (Hub-cell (World-hub world)) hub-reach))

    (: building-nodes (-> World (List Node)))
    (define (building-nodes world)
      (map (lambda (b) (Node (Building-id b) (Building-cell b) (building-reach b)))
           (filter built? (World-buildings world))))

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
                          (filter-map (lambda (k) (link world nodes i (+ k (+ i 1))))
                                      (iota (- (vector-length nodes) (+ i 1)))))
                        (iota (vector-length nodes)))))

    (: link (-> World (Vector Node) I64 I64 (Option Link)))
    (define (link world nodes i j)
      (let ((a (vector-ref nodes i)) (b (vector-ref nodes j)))
        (if (wire-reaches? world (Node-cell a) (Node-reach a) (Node-cell b) (Node-reach b))
            (Some (Link i j (distance-squared (Node-cell a) (Node-cell b))))
            (None))))

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
           (match (grow nodes
                        links
                        (vector-set inside root #t)
                        wires
                        (list (vector-ref nodes root)))
             ((Pair (Pair inside wires) tree)
              (loop inside wires (match powered ((None) (Some (reverse tree))) (_ powered))))))
          ((None) (Pair (match powered ((Some tree) tree) ((None) (Nil))) (reverse wires))))))

    ;; Adds the shortest link from the tree to a new node until none is left.
    (: grow
       (-> (Vector Node)
           (List Link)
           (Vector Bool)
           (List Wire)
           (List Node)
           (Pair (Pair (Vector Bool) (List Wire)) (List Node))))
    (define (grow nodes links inside wires tree)
      (match (shortest-crossing links inside)
        ((Some l)
         (let* ((outward (vector-ref inside (Link-a l)))
                (from (if outward (Link-a l) (Link-b l)))
                (to (if outward (Link-b l) (Link-a l))))
           (grow nodes
                 links
                 (vector-set inside to #t)
                 (Cons (Wire (vector-ref nodes from) (vector-ref nodes to)) wires)
                 (Cons (vector-ref nodes to) tree))))
        ((None) (Pair (Pair inside wires) tree))))

    ;; The first of the shortest links with one end inside, so ties go to
    ;; the older pair.
    (: shortest-crossing (-> (List Link) (Vector Bool) (Option Link)))
    (define (shortest-crossing links inside)
      (fold-left (lambda (best l)
                   (if (and (not (eq-bool? (vector-ref inside (Link-a l))
                                           (vector-ref inside (Link-b l))))
                            (match best ((Some b) (< (Link-cost l) (Link-cost b))) ((None) #t)))
                       (Some l)
                       best))
                 (None) links))

    (: eq-bool? (-> Bool Bool Bool))
    (define (eq-bool? a b)
      (if a b (not b)))

    (: filter-map (All (A B) (-> (-> A (Option B)) (List A) (List B))))
    (define (filter-map f items)
      (fold-right
       (lambda (item kept) (match (f item) ((Some value) (Cons value kept)) ((None) kept)))
       (Nil)
       items))

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

    ;; ---- Rewiring ----

    ;; Recomputes the wires, power and sight after the buildings change. A
    ;; cell once visible stays explored.
    (: rewire (-> World World))
    (define (rewire world)
      (let* ((nodes (list->vector (Cons (hub-node world) (building-nodes world))))
             (spanned (span nodes (links world nodes))))
        (explore (structures-changed (World-visible-set (World-network-set world
                                                                           (Network
                                                                            (Pair-second spanned)
                                                                            (Pair-first spanned)))
                                                        (lit-cells (Pair-first spanned)))))))

    (: explore (-> World World))
    (define (explore world)
      (let* ((explored (World-explored world)) (visible (World-visible world))
             (fresh (filter (lambda (index)
                              (and (vector-ref visible index) (not (vector-ref explored index))))
                            (iota (vector-length visible)))))
        (if (null? fresh)
            world
            (World-explored-version-set
             (World-reveal-set (World-explored-set world
                                                   (vector-generate (vector-length visible)
                                                                    (lambda (index)
                                                                      (or
                                                                       (vector-ref explored index)
                                                                       (vector-ref visible
                                                                                   index)))))
                               (reveal-around explored (map index-cell fresh) (World-tick world)))
             (+ (World-explored-version world) 1)))))

    ;; The newly explored cells unveil from their middle outward.
    (: reveal-around (-> (Vector Bool) (List Cell) I64 Reveal))
    (define (reveal-around before cells tick)
      (let* ((count (length cells))
             (center (Cell (quotient (fold-left + 0 (map Cell-x cells)) count)
                           (quotient (fold-left + 0 (map Cell-y cells)) count))))
        (Reveal before
                center
                (+ 1
                   (integer-sqrt
                    (fold-left max 0 (map (lambda (cell) (distance-squared cell center)) cells))))
                tick)))

    ;; A decided game shows the whole map for inspection, at once: the world
    ;; is still, so nothing could unveil.
    (: uncover (-> World World))
    (define (uncover world)
      (let ((everything (make-vector (* map-size map-size) #t)) (reveal (World-reveal world)))
        (structures-changed
         (World-explored-version-set (World-reveal-set (World-visible-set (World-explored-set world
                                                                                              everything)
                                                                          everything)
                                                       (Reveal-tick-set reveal -1000))
                                     (+ (World-explored-version world) 1)))))

    ))
