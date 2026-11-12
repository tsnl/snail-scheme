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
   Work-progress-set
   remaining-work
   rush-price
   work-refund
   Building
   Building-level-set
   Building-health-set
   Building-aim-set
   Building-work-set
   built?
   building-reach
   invested
   Hub
   Hub-health-set
   Hub-slots-set
   Hub-work-set
   hub-health
   hub-reach
   maximum-slots
   slot-cost
   slot-duration
   hub-cell?
   Crystal
   Crystal-reserve-set
   Nest
   Nest-health-set
   nest-health
   Behavior
   Minion
   Raider
   Beast
   Enemy
   Enemy-cell-set
   Enemy-previous-set
   Enemy-health-set
   Enemy-aggro-set
   Dig
   rock-health
   Alert
   Route
   Shot
   Outcome
   Playing
   Won
   Lost
   Resigned
   Ledger
   Ledger-kills-set
   Ledger-lost-set
   Node
   Wire
   Network
   Reveal
   World
   World-tick-set
   World-started-set
   World-outcome-set
   World-hub-set
   World-buildings-set
   World-nests-set
   World-enemies-set
   World-shots-set
   World-digs-set
   World-alerts-set
   World-routes-set
   World-ledger-set
   World-next-order-set
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
   (snail core base)
   (snail shell wire)
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

    (define (kind-name (kind Kind)) (→ String)
      (match kind
        ((Extractor) "Extractor")
        ((Pylon) "Pylon")
        ((Turret) "Turret")))

    (define (kind-health (kind Kind)) (→ I64)
      (match kind
        ((Extractor) 140)
        ((Pylon) 90)
        ((Turret) 100)))

    ;; How far a powered building of `kind` at `level` sees, and the longest
    ;; wire it can hold.
    (define (kind-reach (kind Kind) (level I64)) (→ I64)
      (match kind
        ((Extractor) 4)
        ((Pylon) (case level ((1) 7) ((2) 10) (else 12)))
        ((Turret) 6)))

    (define maximum-level (→ I64) 3)

    ;; The energy and ticks of work that raise a `kind` from `level`.
    (define (raise-cost (kind Kind) (level I64)) (→ I64)
      (match kind
        ((Extractor) (case level ((0) 25) ((1) 40) (else 160)))
        ((Pylon) (case level ((0) 25) ((1) 25) (else 50)))
        ((Turret) (case level ((0) 50) (else 25)))))

    (define (raise-duration (kind Kind) (level I64)) (→ I64)
      (match kind
        ((Extractor) (case level ((0) 30) ((1) 40) (else 60)))
        ((Pylon) (case level ((0) 20) ((1) 30) (else 50)))
        ((Turret) (case level ((0) 40) ((1) 40) (else 60)))))

    (define (built? (building Building)) (→ Bool)
      (> (● building level) 0))

    (define (building-reach (building Building)) (→ I64)
      (kind-reach (● building kind) (max 1 (● building level))))

    ;; Everything paid for the levels a building has reached.
    (define (invested (building Building)) (→ I64)
      (fold-left +
                 0
                 (map (lambda (level) (raise-cost (● building kind) level))
                      (iota (● building level)))))

    ;; ---- Work ----

    (define (remaining-work (work Work)) (→ I64)
      (max 0 (- (● work duration) (● work progress))))

    ;; Rushing finishes the work at once for four times the share of its
    ;; cost that remains, rounded up, so rushing as it is ordered costs five
    ;; times the price in all, and rushing later costs less.
    (define (rush-price (work Work)) (→ I64)
      (quotient (+ (* 4 (* (● work cost) (remaining-work work))) (- (● work duration) 1))
                (● work duration)))

    ;; Cancelling returns the whole cost.
    (define (work-refund (work Work)) (→ I64)
      (● work cost))

    ;; ---- The hub ----

    ;; The hub covers the three by three cells around its center. Its work
    ;; adds a build slot: the number of works that progress at once.
    (struct Hub
      ((cell Cell)
       (health I64)
       (slots I64)
       (work (Option Work))))

    (define hub-health (→ I64) 600)

    (define hub-reach (→ I64) 9)

    (define maximum-slots (→ I64) 3)

    (define (slot-cost (slots I64)) (→ I64)
      (* 100 slots))

    (define (slot-duration (slots I64)) (→ I64)
      (+ 20 (* 30 slots)))

    (define (hub-cell? (hub Hub) (cell Cell)) (→ Bool)
      (and (<= (abs (- (● cell x) (● (● hub cell) x))) 1)
           (<= (abs (- (● cell y) (● (● hub cell) y))) 1)))

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

    (define nest-health (→ I64) 900)

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

    (define rock-health (→ I64) 80)

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

    (define starting-energy (→ I64) 160)

    ;; Each crystal site holds its full reserve, the nests cover theirs, and
    ;; each front holds a nest. The colony starts with its hub alone, the
    ;; ground around it already unveiled.
    (define (new-world (seed I64)) (→ World)
      (let ((world (first-world seed)))
        (World-reveal-set world (Reveal-tick-set (● world reveal) -1000))))

    (define (first-world (seed I64)) (→ World)
      (let ((land (new-land (land-seed seed))) (cells (* map-size map-size)))
        (rewire (World seed
                       land
                       0
                       #f
                       (Playing)
                       starting-energy
                       (Hub (● land hub) hub-health 1 (None))
                       (Nil)
                       (append (map site-crystal (● land sites))
                               (map nest-crystal (● land fronts)))
                       (map-indexed (lambda (front cell) (Nest front cell nest-health))
                                    (● land fronts))
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
                       (Reveal (make-vector cells #f) (● land hub) 0 0)
                       0
                       0))))

    (define (site-crystal (site Site)) (→ Crystal)
      (Crystal (● site cell) (● site rate) (* reserve-per-rate (● site rate))))

    (define (nest-crystal (cell Cell)) (→ Crystal)
      (Crystal cell nest-rate (* reserve-per-rate nest-rate)))

    (define (playing? (world World)) (→ Bool)
      (match (● world outcome)
        ((Playing) #t)
        (_ #f)))

    ;; The opening: the game is in play, and its first extractor is still
    ;; to be ordered.
    (define (opening? (world World)) (→ Bool)
      (and (not (● world started)) (playing? world)))

    (define (fresh-id (world World)) (→ (Pair I64 World))
      (Pair (● world next-id) (World-next-id-set world (+ (● world next-id) 1))))

    ;; ---- Lookups and replacements ----

    (define (building (world World) (id I64)) (→ (Option Building))
      (find (lambda (b) (= (● b id) id)) (● world buildings)))

    (define (building-at (world World) (cell Cell)) (→ (Option Building))
      (find (lambda (b) (cell=? (● b cell) cell)) (● world buildings)))

    (define (put-building (world World) (building Building)) (→ World)
      (World-buildings-set world
                           (map
                            (lambda (b) (if (= (● b id) (● building id)) building b))
                            (● world buildings))))

    (define (remove-building (world World) (id I64)) (→ World)
      (rewire (World-buildings-set world
                                   (filter (lambda (b) (not (= (● b id) id)))
                                           (● world buildings)))))

    (define (crystal-at (world World) (cell Cell)) (→ (Option Crystal))
      (find (lambda (crystal) (cell=? (● crystal cell) cell)) (● world crystals)))

    (define (put-crystal (world World) (crystal Crystal)) (→ World)
      (World-crystals-set world
                          (map (lambda (c)
                                 (if (cell=? (● c cell) (● crystal cell)) crystal c))
                               (● world crystals))))

    (define (nest-at (world World) (cell Cell)) (→ (Option Nest))
      (find (lambda (nest) (cell=? (● nest cell) cell)) (● world nests)))

    ;; Rock that enemies have dug through for good.
    (define (opened? (world World) (cell Cell)) (→ Bool)
      (vector-ref (● world opened) (cell-index cell)))

    ;; Opening rock changes every route and may clear wires and shots.
    (define (open-rock (world World) (cell Cell)) (→ World)
      (rewire (World-routes-set
               (World-opened-set world (vector-set (● world opened) (cell-index cell) #t))
               (Nil))))

    ;; Spending and earning keep energy and the ledger in step; a refund is
    ;; negative spending.
    (define (spend (world World) (amount I64)) (→ World)
      (World-ledger-set (World-energy-set world (- (● world energy) amount))
                        (Ledger-spent-set (● world ledger)
                                          (+ (● (● world ledger) spent) amount))))

    (define (earn (world World) (amount I64)) (→ World)
      (World-ledger-set (World-energy-set world (+ (● world energy) amount))
                        (Ledger-produced-set (● world ledger)
                                             (+ (● (● world ledger) produced) amount))))

    (define (structures-changed (world World)) (→ World)
      (World-structure-version-set world (+ (● world structure-version) 1)))

    ;; ---- Wires and power ----

    ;; Wires, shots and sight lines cross everything but intact rock.
    (define (clear-line? (world World) (from Cell) (to Cell)) (→ Bool)
      (every? (lambda (cell)
                (match (ground-at (● world land) cell) ((Rock) (opened? world cell)) (_ #t)))
              (line-cells from to)))

    ;; A wire reaches as far as the longer reach of its two ends.
    (define (wire-reaches? (world World) (a Cell) (reach-a I64) (b Cell) (reach-b I64)) (→ Bool)
      (and (within? a b (max reach-a reach-b)) (clear-line? world a b)))

    (define (hub-node (world World)) (→ Node)
      (Node 0 (● (● world hub) cell) hub-reach))

    (define (building-nodes (world World)) (→ (List Node))
      (map (lambda (b) (Node (● b id) (● b cell) (building-reach b)))
           (filter built? (● world buildings))))

    ;; A pair of nodes a wire could join, by their places in the list of
    ;; nodes, with the squared length that ranks it.
    (struct Link
      ((a I64)
       (b I64)
       (cost I64)))

    ;; Every pair of nodes a wire reaches, each pair once, in node order.
    (define (links (world World) (nodes (Vector Node))) (→ (List Link))
      (concatenate (map (lambda (i)
                          (filter-map (lambda (k) (link world nodes i (+ k (+ i 1))))
                                      (iota (- (vector-length nodes) (+ i 1)))))
                        (iota (vector-length nodes)))))

    (define (link (world World) (nodes (Vector Node)) (i I64) (j I64)) (→ (Option Link))
      (let ((a (vector-ref nodes i)) (b (vector-ref nodes j)))
        (if (wire-reaches? world (● a cell) (● a reach) (● b cell) (● b reach))
            (Some (Link i j (distance-squared (● a cell) (● b cell))))
            (None))))

    ;; The wires run along a minimum spanning forest of the links: a tree
    ;; grown from the hub, always by the shortest link that reaches a new
    ;; node, then a tree for each group of nodes it could not reach. The
    ;; hub's tree is the powered network, so it reaches exactly what the
    ;; links do, and losing a node may rewire it along links not drawn
    ;; before. Each wire runs from the node it was reached from.
    (define (span (nodes (Vector Node)) (links (List Link))) (→ (Pair (List Node) (List Wire)))
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
    (define (grow (nodes (Vector Node))
                  (links (List Link))
                  (inside (Vector Bool))
                  (wires (List Wire))
                  (tree (List Node)))
      (→ (Pair (Pair (Vector Bool) (List Wire)) (List Node)))
      (match (shortest-crossing links inside)
        ((Some l)
         (let* ((outward (vector-ref inside (● l a)))
                (from (if outward (● l a) (● l b)))
                (to (if outward (● l b) (● l a))))
           (grow nodes
                 links
                 (vector-set inside to #t)
                 (Cons (Wire (vector-ref nodes from) (vector-ref nodes to)) wires)
                 (Cons (vector-ref nodes to) tree))))
        ((None) (Pair (Pair inside wires) tree))))

    ;; The first of the shortest links with one end inside, so ties go to
    ;; the older pair.
    (define (shortest-crossing (links (List Link)) (inside (Vector Bool))) (→ (Option Link))
      (fold-left (lambda (best l)
                   (if (and (not (eq-bool? (vector-ref inside (● l a))
                                           (vector-ref inside (● l b))))
                            (match best ((Some b) (< (● l cost) (● b cost))) ((None) #t)))
                       (Some l)
                       best))
                 (None) links))

    (define (eq-bool? (a Bool) (b Bool)) (→ Bool)
      (if a b (not b)))

    (define (filter-map (f (Fn A → (Option B))) (items (List A))) (→ (List B)) (∀ A B)
      (fold-right
       (lambda (item kept) (match (f item) ((Some value) (Cons value kept)) ((None) kept)))
       (Nil)
       items))

    (define (powered? (world World) (id I64)) (→ Bool)
      (any? (lambda (node) (= (● node id) id)) (● (● world network) powered)))

    ;; ---- Sight ----

    ;; Every cell within reach of one of `nodes`.
    (define (lit-cells (nodes (List Node))) (→ (Vector Bool))
      (unsafe-total
       (lambda ()
         (let ((seen (make-array (* map-size map-size) #f)))
           (for-each (lambda (node) (light! seen (● node cell) (● node reach))) nodes)
           (array->vector seen)))))

    (define (light! (seen (Array Bool)) (center Cell) (radius I64)) (→ Unit) (! mut)
      (let ((offsets (map (lambda (i) (- i radius)) (iota (+ 1 (* 2 radius))))))
        (for-each (lambda (dy)
                    (for-each (lambda (dx)
                                (let ((cell (Cell (+ (● center x) dx) (+ (● center y) dy))))
                                  (when (and (in-bounds? cell) (within? cell center radius))
                                    (array-set! seen (cell-index cell) #t))))
                              offsets))
                  offsets)))

    (define (visible? (world World) (cell Cell)) (→ Bool)
      (vector-ref (● world visible) (cell-index cell)))

    (define (explored? (world World) (cell Cell)) (→ Bool)
      (vector-ref (● world explored) (cell-index cell)))

    ;; ---- Rewiring ----

    ;; Recomputes the wires, power and sight after the buildings change. A
    ;; cell once visible stays explored.
    (define (rewire (world World)) (→ World)
      (let* ((nodes (list->vector (Cons (hub-node world) (building-nodes world))))
             (spanned (span nodes (links world nodes))))
        (explore (structures-changed (World-visible-set (World-network-set world
                                                                           (Network
                                                                            (● spanned second)
                                                                            (● spanned first)))
                                                        (lit-cells (● spanned first)))))))

    (define (explore (world World)) (→ World)
      (let* ((explored (● world explored)) (visible (● world visible))
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
                               (reveal-around explored (map index-cell fresh) (● world tick)))
             (+ (● world explored-version) 1)))))

    ;; The newly explored cells unveil from their middle outward.
    (define (reveal-around (before (Vector Bool)) (cells (List Cell)) (tick I64)) (→ Reveal)
      (let* ((count (length cells))
             (center
              (Cell (quotient (fold-left + 0 (map (lambda (record) (● record x)) cells)) count)
                    (quotient (fold-left + 0 (map (lambda (record) (● record y)) cells)) count))))
        (Reveal before
                center
                (+ 1
                   (integer-sqrt
                    (fold-left max 0 (map (lambda (cell) (distance-squared cell center)) cells))))
                tick)))

    ;; A decided game shows the whole map for inspection, at once: the world
    ;; is still, so nothing could unveil.
    (define (uncover (world World)) (→ World)
      (let ((everything (make-vector (* map-size map-size) #t)) (reveal (● world reveal)))
        (structures-changed
         (World-explored-version-set (World-reveal-set (World-visible-set (World-explored-set world
                                                                                              everything)
                                                                          everything)
                                                       (Reveal-tick-set reveal -1000))
                                     (+ (● world explored-version) 1)))))

    ))
