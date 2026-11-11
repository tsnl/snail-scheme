;; The colony's rules: the orders a player can give, the work that raises
;; sites and buildings while they hold a hub slot, and the extractors that
;; turn crystal into energy.
;;
;; `act` is the only way an order changes the world. It either rejects the
;; order with the reason, leaving the world as it was, or returns the world
;; with the order applied and paid for.
(define-library (siegework colony)
  (export
   Action
   Build
   Upgrade
   Rush
   Cancel
   Scavenge
   Repair
   Resign
   Rejection
   rejection-text
   later?
   repair-price
   act
   check
   Task
   Owner
   OfHub
   OfBuilding
   tasks
   work
   produce)
  (import
   (snail core base)
   (snail shell wire)
   (siegework grid)
   (siegework terrain)
   (siegework world))
  (begin

    ;; ---- Orders ----

    ;; Orders name cells rather than ids, so a journal of them still means
    ;; the same places when it is replayed under changed rules.
    (enum Action
      (Build ((kind Kind) (cell Cell) (rush Bool)))
      (Upgrade ((cell Cell)))
      (Rush ((cell Cell)))
      (Cancel ((cell Cell)))
      (Scavenge ((cell Cell)))
      (Repair)
      (Resign)
      (deriving Serialize Deserialize))

    (enum Rejection
      (Finished)
      (NotStarted)
      (OutsideMap)
      (Unseen)
      (NotOpen)
      (Occupied)
      (NeedsCrystal)
      (CrystalSite)
      (Depleted)
      (OutOfReach)
      (CannotAfford)
      (NothingThere)
      (HubOnly)
      (Unfinished)
      (Busy)
      (Idle)
      (MaximumLevel)
      (FullHealth))

    (define (rejection-text (rejection Rejection)) (→ String)
      (match rejection
        ((Finished) "The game is over.")
        ((NotStarted) "Start with an extractor on a crystal.")
        ((OutsideMap) "That is outside the map.")
        ((Unseen) "Nothing powered can see there.")
        ((NotOpen) "Only open ground can be built on.")
        ((Occupied) "Something is already there.")
        ((NeedsCrystal) "Extractors go on crystals.")
        ((CrystalSite) "Crystals take only extractors.")
        ((Depleted) "That crystal is exhausted.")
        ((OutOfReach) "No powered building can wire to it.")
        ((CannotAfford) "Not enough energy.")
        ((NothingThere) "There is nothing to change there.")
        ((HubOnly) "The hub cannot be scavenged.")
        ((Unfinished) "Finish building it first.")
        ((Busy) "It is already working.")
        ((Idle) "There is no work to change.")
        ((MaximumLevel) "It is fully upgraded.")
        ((FullHealth) "The hub is undamaged.")))

    ;; Whether an order refused for this reason may still succeed on the same
    ;; cell once energy, work in progress or the network catch up, rather
    ;; than never applying there.
    (define (later? (rejection Rejection)) (→ Bool)
      (match rejection
        ((NotStarted) #t)
        ((Unseen) #t)
        ((OutOfReach) #t)
        ((CannotAfford) #t)
        ((Unfinished) #t)
        ((Busy) #t)
        (_ #f)))

    ;; Checks the order, then applies it. Every order needs a game in play.
    ;; Until the first extractor is ordered, an order that would otherwise
    ;; be accepted waits, so its rejection still tells whether it could
    ;; apply here at all.
    (define (act (world World) (action Action)) (→ (Result World Rejection))
      (if (playing? world)
          (match (apply-order world action)
            ((Ok next)
             (if (or (● world started) (opening-order? action)) (Ok next) (Err (NotStarted))))
            ((Err rejection) (Err rejection)))
          (Err (Finished))))

    (define (apply-order (world World) (action Action)) (→ (Result World Rejection))
      (match action
        ((Build kind cell rush) (build world kind cell rush))
        ((Upgrade cell) (with-owner world cell upgrade))
        ((Rush cell) (with-owner world cell rush))
        ((Cancel cell) (with-owner world cell cancel))
        ((Scavenge cell) (with-owner world cell scavenge))
        ((Repair) (repair world))
        ((Resign) (Ok (uncover (World-outcome-set world (Resigned)))))))

    (define (opening-order? (action Action)) (→ Bool)
      (match action
        ((Build (Extractor) _ _) #t)
        ((Resign) #t)
        (_ #f)))

    ;; Why an order would be rejected, if it would.
    (define (check (world World) (action Action)) (→ (Option Rejection))
      (match (act world action)
        ((Ok _) (None))
        ((Err rejection) (Some rejection))))

    (define (pay (world World) (price I64) (apply (dyn (Fn World → World))))
      (→ (Result World Rejection))
      (if (< (● world energy) price) (Err (CannotAfford)) (Ok (apply (spend world price)))))

    ;; ---- Building ----

    ;; A site needs visible open ground that nothing occupies, a crystal exactly
    ;; when it is an extractor, and a powered building that can wire to it.
    (define (build (world World) (kind Kind) (cell Cell) (rush Bool)) (→ (Result World Rejection))
      (let ((extractor? (match kind ((Extractor) #t) (_ #f))) (crystal (crystal-at world cell)))
        (cond ((not (in-bounds? cell)) (Err (OutsideMap)))
              ((not (visible? world cell)) (Err (Unseen)))
              ((match (ground-at (● world land) cell) ((Open) #f) (_ #t)) (Err (NotOpen)))
              ((occupied? world cell) (Err (Occupied)))
              ((and extractor? (null-option? crystal)) (Err (NeedsCrystal)))
              ((and (not extractor?) (not (null-option? crystal))) (Err (CrystalSite)))
              ((and extractor? (exhausted? crystal)) (Err (Depleted)))
              ((not (in-reach? world kind cell)) (Err (OutOfReach)))
              (else (place world kind cell (and rush (● world started)))))))

    ;; The colony's first extractor is ready at once, so a new game starts
    ;; producing; a rushed order is ready at once for five times its cost;
    ;; any other joins the queue.
    (define (place (world World) (kind Kind) (cell Cell) (rush Bool)) (→ (Result World Rejection))
      (let* ((work (new-work world (raise-cost kind 0) (raise-duration kind 0)))
             (ready (or rush (not (● world started)))))
        (pay world
             (+ (● work cost) (if rush (rush-price work) 0))
             (lambda (world) (place-site world kind cell work ready)))))

    (define (occupied? (world World) (cell Cell)) (→ Bool)
      (or (hub-cell? (● world hub) cell)
          (not (null-option? (building-at world cell)))
          (match (nest-at world cell)
            ((Some nest) (> (● nest health) 0))
            ((None) #f))))

    (define (null-option? (option (Option T))) (→ Bool) (∀ T) (⊨ (Copy T))
      (match option
        ((Some _) #f)
        ((None) #t)))

    (define (exhausted? (crystal (Option Crystal))) (→ Bool)
      (match crystal
        ((Some crystal) (= (● crystal reserve) 0))
        ((None) #t)))

    ;; Whether a powered building could wire to a new `kind` at `cell`.
    (define (in-reach? (world World) (kind Kind) (cell Cell)) (→ Bool)
      (any? (lambda (node)
              (wire-reaches? world (● node cell) (● node reach) cell (kind-reach kind 1)))
            (● (● world network) powered)))

    ;; New work joins the end of the queue.
    (define (new-work (world World) (cost I64) (duration I64)) (→ Work)
      (Work (● world next-order) cost duration 0))

    (define (place-site (world World) (kind Kind) (cell Cell) (work Work) (ready Bool)) (→ World)
      (match (fresh-id world)
        ((Pair id world)
         (if ready
             (rewire (World-started-set (add-building world
                                                      (Building id
                                                                kind
                                                                cell
                                                                1
                                                                (kind-health kind)
                                                                (None)
                                                                (None)))
                                        #t))
             (structures-changed (World-next-order-set (add-building world
                                                                     (Building id
                                                                               kind
                                                                               cell
                                                                               0
                                                                               (kind-health kind)
                                                                               (Some work)
                                                                               (None)))
                                                       (+ (● world next-order) 1)))))))

    (define (add-building (world World) (building Building)) (→ World)
      (World-buildings-set world (append (● world buildings) (list building))))

    ;; ---- Owners ----

    ;; What an order or a work belongs to: the hub, or a building as found in
    ;; the current world. Upgrades, rushes, cancellations and scavenging name
    ;; any cell of the hub or of a building.
    (enum Owner
      (OfHub)
      (OfBuilding ((building Building))))

    (define (with-owner (world World)
                        (cell Cell)
                        (order (dyn (Fn World Owner → (Result World Rejection)))))
      (→ (Result World Rejection))
      (cond ((hub-cell? (● world hub) cell) (order world (OfHub)))
            (else (match (building-at world cell)
                    ((Some b) (order world (OfBuilding b)))
                    ((None) (Err (NothingThere)))))))

    (define (owner-work (world World) (owner Owner)) (→ (Option Work))
      (match owner
        ((OfHub) (● (● world hub) work))
        ((OfBuilding b) (● b work))))

    (define (set-owner-work (world World) (owner Owner) (work (Option Work))) (→ World)
      (match owner
        ((OfHub) (World-hub-set world (Hub-work-set (● world hub) work)))
        ((OfBuilding b) (put-building world (Building-work-set b work)))))

    ;; ---- Upgrades ----

    ;; The hub's upgrade adds a build slot; a building's adds a level.
    (define (upgrade (world World) (owner Owner)) (→ (Result World Rejection))
      (match (upgrade-work world owner)
        ((Ok work)
         (pay world
              (● work cost)
              (lambda (world) (structures-changed (set-owner-work world owner (Some work))))))
        ((Err rejection) (Err rejection))))

    (define (upgrade-work (world World) (owner Owner)) (→ (Result Work Rejection))
      (match owner
        ((OfHub) (let ((slots (● (● world hub) slots)))
                   (cond ((not (null-option? (● (● world hub) work))) (Err (Busy)))
                         ((>= slots maximum-slots) (Err (MaximumLevel)))
                         (else (Ok (new-work world (slot-cost slots) (slot-duration slots)))))))
        ((OfBuilding b) (let ((level (● b level)) (kind (● b kind)))
                          (cond ((not (built? b)) (Err (Unfinished)))
                                ((not (null-option? (● b work))) (Err (Busy)))
                                ((>= level maximum-level) (Err (MaximumLevel)))
                                (else (Ok (new-work world
                                                    (raise-cost kind level)
                                                    (raise-duration kind level)))))))))

    ;; ---- Rushing and cancelling ----

    (define (rush (world World) (owner Owner)) (→ (Result World Rejection))
      (match (owner-work world owner)
        ((Some work) (pay world (rush-price work) (lambda (world) (finish world owner))))
        ((None) (Err (Idle)))))

    ;; Cancelling a site removes it; cancelling an upgrade leaves the building
    ;; at its level.
    (define (cancel (world World) (owner Owner)) (→ (Result World Rejection))
      (match (owner-work world owner)
        ((Some work)
         (Ok (structures-changed (drop-work (spend world (- 0 (work-refund work))) owner))))
        ((None) (Err (Idle)))))

    (define (drop-work (world World) (owner Owner)) (→ World)
      (match owner
        ((OfBuilding b)
         (if (built? b)
             (set-owner-work world owner (None))
             (remove-building world (● b id))))
        ((OfHub) (set-owner-work world owner (None)))))

    ;; ---- Scavenging and repair ----

    ;; Scavenging removes an idle building and returns a fifth of everything
    ;; paid for its levels.
    (define (scavenge (world World) (owner Owner)) (→ (Result World Rejection))
      (match owner
        ((OfHub) (Err (HubOnly)))
        ((OfBuilding b) (cond ((not (built? b)) (Err (Unfinished)))
                              ((not (null-option? (● b work))) (Err (Busy)))
                              (else
                               (Ok (remove-building (spend world (- 0 (quotient (invested b) 5)))
                                                    (● b id))))))))

    ;; Repair restores the hub to full health, at one energy for each two
    ;; health it lacks.
    (define (repair (world World)) (→ (Result World Rejection))
      (let* ((hub (● world hub)) (missing (- hub-health (● hub health))))
        (if (= missing 0)
            (Err (FullHealth))
            (pay world
                 (repair-price hub)
                 (lambda (world) (World-hub-set world (Hub-health-set hub hub-health)))))))

    (define (repair-price (hub Hub)) (→ I64)
      (quotient (+ (- hub-health (● hub health)) 1) 2))

    ;; ---- Work ----

    ;; Each queued work with its owner, whether the owner is powered, and
    ;; whether the work holds a slot.
    (struct Task
      ((owner Owner)
       (work Work)
       (supplied Bool)
       (active Bool)))

    ;; Works in the order they were given. The first ones whose owner is
    ;; powered hold the hub's slots; a site counts as powered when a powered
    ;; building can wire to it. An unpowered work keeps its progress and
    ;; leaves its slot to the next. A work changes only its own owner, so
    ;; the owners found here stay current while the works progress.
    (define (tasks (world World)) (→ (List Task))
      (let loop ((pending (queued world)) (free (● (● world hub) slots)) (listed (Nil)))
        (match pending
          ((Nil) (reverse listed))
          ((Cons (Pair owner work) rest)
           (let* ((supplied (supplied? world owner)) (active (and (> free 0) supplied)))
             (loop rest
                   (if active (- free 1) free)
                   (Cons (Task owner work supplied active) listed)))))))

    (define (queued (world World)) (→ (List (Pair Owner Work)))
      (insertion-sort (lambda (a b) (< (● (● a second) order) (● (● b second) order)))
                      (append (match (● (● world hub) work)
                                ((Some work) (list (Pair (OfHub) work)))
                                ((None) (Nil)))
                              (filter-map (lambda (b)
                                            (match (● b work)
                                              ((Some work) (Some (Pair (OfBuilding b) work)))
                                              ((None) (None))))
                                          (● world buildings)))))

    (define (supplied? (world World) (owner Owner)) (→ Bool)
      (match owner
        ((OfHub) #t)
        ((OfBuilding b)
         (if (built? b)
             (powered? world (● b id))
             (in-reach? world (● b kind) (● b cell))))))

    ;; Active works progress, and finished ones raise their owner.
    (define (work (world World)) (→ World)
      (fold-left (lambda (world task) (if (● task active) (progress world task) world))
                 world
                 (tasks world)))

    (define (progress (world World) (task Task)) (→ World)
      (let ((work (Work-progress-set (● task work) (+ (● (● task work) progress) 1))))
        (if (> (remaining-work work) 0)
            (set-owner-work world (● task owner) (Some work))
            (finish world (● task owner)))))

    ;; Finished work raises its owner: the hub gains a build slot, and a
    ;; building a level and its full health.
    (define (finish (world World) (owner Owner)) (→ World)
      (match owner
        ((OfHub)
         (let ((hub (● world hub)))
           (World-hub-set world (Hub-work-set (Hub-slots-set hub (+ (● hub slots) 1)) (None)))))
        ((OfBuilding b)
         (rewire (put-building world
                               (Building-health-set
                                (Building-work-set (Building-level-set b (+ (● b level) 1))
                                                   (None))
                                (kind-health (● b kind))))))))

    ;; ---- Production ----

    ;; Every second each powered extractor draws its crystal's rate for each
    ;; of its levels, until the reserve runs out.
    (define (produce (world World)) (→ World)
      (if (= (remainder (● world tick) 10) 0)
          (fold-left extract
                     world
                     (filter
                      (lambda (b) (and (built? b) (extractor? b) (powered? world (● b id))))
                      (● world buildings)))
          world))

    (define (extractor? (building Building)) (→ Bool)
      (match (● building kind)
        ((Extractor) #t)
        (_ #f)))

    (define (extract (world World) (extractor Building)) (→ World)
      (match (crystal-at world (● extractor cell))
        ((Some crystal)
         (let ((amount (min (● crystal reserve)
                            (* (● crystal rate) (● extractor level)))))
           (earn
            (put-crystal world (Crystal-reserve-set crystal (- (● crystal reserve) amount)))
            amount)))
        ((None) world)))

    ;; ---- Lists ----

    (define (filter-map (f (dyn (Fn A → (Option B)))) (items (List A))) (→ (List B)) (∀ A B)
      (fold-right
       (lambda (item kept) (match (f item) ((Some value) (Cons value kept)) ((None) kept)))
       (Nil)
       items))

    ;; Stable, for the handful of queued works.
    (define (insertion-sort (before? (dyn (Fn T T → Bool))) (items (List T)))
      (→ (List T))
      (∀ T)
      (⊨ (Copy T))
      (fold-left (lambda (sorted item) (insert before? item sorted)) (Nil) items))

    (define (insert (before? (dyn (Fn T T → Bool))) (item T) (sorted (List T)))
      (→ (List T))
      (∀ T)
      (⊨ (Copy T))
      (match sorted
        ((Nil) (list item))
        ((Cons first rest)
         (if (before? item first) (Cons item sorted) (Cons first (insert before? item rest))))))

    ))
