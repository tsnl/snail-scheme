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
   Task-owner
   Task-work
   Task-supplied
   Task-active
   Owner
   OfHub
   OfBuilding
   tasks
   work
   produce)
  (import
   (lofi base)
   (lofi wire)
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

    (: rejection-text (-> Rejection String))
    (define (rejection-text rejection)
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
    (: later? (-> Rejection Bool))
    (define (later? rejection)
      (match rejection
        ((NotStarted) #t)
        ((Unseen) #t)
        ((OutOfReach) #t)
        ((CannotAfford) #t)
        ((Unfinished) #t)
        ((Busy) #t)
        (_ #f)))

    ;; Checks the order, then applies it. Every order needs a game in play,
    ;; and until the first extractor is ordered nothing else may be.
    (: act (-> World Action (Result World Rejection)))
    (define (act world action)
      (cond ((not (playing? world)) (Err (Finished)))
            ((not (or (World-started world) (opening? action))) (Err (NotStarted)))
            (else (match action
                    ((Build kind cell rush) (build world kind cell rush))
                    ((Upgrade cell) (with-owner world cell upgrade))
                    ((Rush cell) (with-owner world cell rush))
                    ((Cancel cell) (with-owner world cell cancel))
                    ((Scavenge cell) (with-owner world cell scavenge))
                    ((Repair) (repair world))
                    ((Resign) (Ok (uncover (World-outcome-set world (Resigned)))))))))

    (: opening? (-> Action Bool))
    (define (opening? action)
      (match action
        ((Build (Extractor) _ _) #t)
        ((Resign) #t)
        (_ #f)))

    ;; Why an order would be rejected, if it would.
    (: check (-> World Action (Option Rejection)))
    (define (check world action)
      (match (act world action)
        ((Ok _) (None))
        ((Err rejection) (Some rejection))))

    (: pay (-> World I64 (-> World World) (Result World Rejection)))
    (define (pay world price apply)
      (if (< (World-energy world) price) (Err (CannotAfford)) (Ok (apply (spend world price)))))

    ;; ---- Building ----

    ;; A site needs visible open ground that nothing occupies, a crystal exactly
    ;; when it is an extractor, and a powered building that can wire to it.
    (: build (-> World Kind Cell Bool (Result World Rejection)))
    (define (build world kind cell rush)
      (let ((extractor? (match kind ((Extractor) #t) (_ #f))) (crystal (crystal-at world cell)))
        (cond ((not (in-bounds? cell)) (Err (OutsideMap)))
              ((not (visible? world cell)) (Err (Unseen)))
              ((match (ground-at (World-land world) cell) ((Open) #f) (_ #t)) (Err (NotOpen)))
              ((occupied? world cell) (Err (Occupied)))
              ((and extractor? (null-option? crystal)) (Err (NeedsCrystal)))
              ((and (not extractor?) (not (null-option? crystal))) (Err (CrystalSite)))
              ((and extractor? (exhausted? crystal)) (Err (Depleted)))
              ((not (in-reach? world kind cell)) (Err (OutOfReach)))
              (else (place world kind cell (and rush (World-started world)))))))

    ;; The colony's first extractor is ready at once, so a new game starts
    ;; producing; a rushed order is ready at once for five times its cost;
    ;; any other joins the queue.
    (: place (-> World Kind Cell Bool (Result World Rejection)))
    (define (place world kind cell rush)
      (let* ((work (new-work world (raise-cost kind 0) (raise-duration kind 0))) (ready (or rush (not (World-started world)))))
        (pay world (+ (Work-cost work) (if rush (rush-price work) 0)) (lambda (world) (place-site world kind cell work ready)))))

    (: occupied? (-> World Cell Bool))
    (define (occupied? world cell)
      (or (hub-cell? (World-hub world) cell)
          (not (null-option? (building-at world cell)))
          (match (nest-at world cell)
            ((Some nest) (> (Nest-health nest) 0))
            ((None) #f))))

    (: null-option? (All (T) (-> (Option T) Bool)))
    (define (null-option? option)
      (match option
        ((Some _) #f)
        ((None) #t)))

    (: exhausted? (-> (Option Crystal) Bool))
    (define (exhausted? crystal)
      (match crystal
        ((Some crystal) (= (Crystal-reserve crystal) 0))
        ((None) #t)))

    ;; Whether a powered building could wire to a new `kind` at `cell`.
    (: in-reach? (-> World Kind Cell Bool))
    (define (in-reach? world kind cell)
      (any? (lambda (node) (wire-reaches? world (Node-cell node) (Node-reach node) cell (kind-reach kind 1)))
            (Network-powered (World-network world))))

    ;; New work joins the end of the queue.
    (: new-work (-> World I64 I64 Work))
    (define (new-work world cost duration)
      (Work (World-next-order world) cost duration 0))

    (: place-site (-> World Kind Cell Work Bool World))
    (define (place-site world kind cell work ready)
      (match (fresh-id world)
        ((Pair id world)
         (if ready
             (rewire (World-started-set (add-building world (Building id kind cell 1 (kind-health kind) (None) (None))) #t))
             (structures-changed (World-next-order-set (add-building world (Building id kind cell 0 (kind-health kind) (Some work) (None)))
                                                       (+ (World-next-order world) 1)))))))

    (: add-building (-> World Building World))
    (define (add-building world building)
      (World-buildings-set world (append (World-buildings world) (list building))))

    ;; ---- Owners ----

    ;; What an order or a work belongs to: the hub, or a building as found in
    ;; the current world. Upgrades, rushes, cancellations and scavenging name
    ;; any cell of the hub or of a building.
    (enum Owner
      (OfHub)
      (OfBuilding ((building Building))))

    (: with-owner (-> World Cell (-> World Owner (Result World Rejection)) (Result World Rejection)))
    (define (with-owner world cell order)
      (cond ((hub-cell? (World-hub world) cell) (order world (OfHub)))
            (else (match (building-at world cell)
                    ((Some b) (order world (OfBuilding b)))
                    ((None) (Err (NothingThere)))))))

    (: owner-work (-> World Owner (Option Work)))
    (define (owner-work world owner)
      (match owner
        ((OfHub) (Hub-work (World-hub world)))
        ((OfBuilding b) (Building-work b))))

    (: set-owner-work (-> World Owner (Option Work) World))
    (define (set-owner-work world owner work)
      (match owner
        ((OfHub) (World-hub-set world (Hub-work-set (World-hub world) work)))
        ((OfBuilding b) (put-building world (Building-work-set b work)))))

    ;; ---- Upgrades ----

    ;; The hub's upgrade adds a build slot; a building's adds a level.
    (: upgrade (-> World Owner (Result World Rejection)))
    (define (upgrade world owner)
      (match (upgrade-work world owner)
        ((Ok work) (pay world (Work-cost work) (lambda (world) (structures-changed (set-owner-work world owner (Some work))))))
        ((Err rejection) (Err rejection))))

    (: upgrade-work (-> World Owner (Result Work Rejection)))
    (define (upgrade-work world owner)
      (match owner
        ((OfHub) (let ((slots (Hub-slots (World-hub world))))
                   (cond ((not (null-option? (Hub-work (World-hub world)))) (Err (Busy)))
                         ((>= slots maximum-slots) (Err (MaximumLevel)))
                         (else (Ok (new-work world (slot-cost slots) (slot-duration slots)))))))
        ((OfBuilding b) (let ((level (Building-level b)) (kind (Building-kind b)))
                          (cond ((not (built? b)) (Err (Unfinished)))
                                ((not (null-option? (Building-work b))) (Err (Busy)))
                                ((>= level maximum-level) (Err (MaximumLevel)))
                                (else (Ok (new-work world (raise-cost kind level) (raise-duration kind level)))))))))

    ;; ---- Rushing and cancelling ----

    (: rush (-> World Owner (Result World Rejection)))
    (define (rush world owner)
      (match (owner-work world owner)
        ((Some work) (pay world (rush-price work) (lambda (world) (finish world owner))))
        ((None) (Err (Idle)))))

    ;; Cancelling a site removes it; cancelling an upgrade leaves the building
    ;; at its level.
    (: cancel (-> World Owner (Result World Rejection)))
    (define (cancel world owner)
      (match (owner-work world owner)
        ((Some work) (Ok (structures-changed (drop-work (spend world (- 0 (work-refund work))) owner))))
        ((None) (Err (Idle)))))

    (: drop-work (-> World Owner World))
    (define (drop-work world owner)
      (match owner
        ((OfBuilding b) (if (built? b) (set-owner-work world owner (None)) (remove-building world (Building-id b))))
        ((OfHub) (set-owner-work world owner (None)))))

    ;; ---- Scavenging and repair ----

    ;; Scavenging removes an idle building and returns a fifth of everything
    ;; paid for its levels.
    (: scavenge (-> World Owner (Result World Rejection)))
    (define (scavenge world owner)
      (match owner
        ((OfHub) (Err (HubOnly)))
        ((OfBuilding b) (cond ((not (built? b)) (Err (Unfinished)))
                              ((not (null-option? (Building-work b))) (Err (Busy)))
                              (else (Ok (remove-building (spend world (- 0 (quotient (invested b) 5))) (Building-id b))))))))

    ;; Repair restores the hub to full health, at one energy for each two
    ;; health it lacks.
    (: repair (-> World (Result World Rejection)))
    (define (repair world)
      (let* ((hub (World-hub world)) (missing (- hub-health (Hub-health hub))))
        (if (= missing 0)
            (Err (FullHealth))
            (pay world (repair-price hub) (lambda (world) (World-hub-set world (Hub-health-set hub hub-health)))))))

    (: repair-price (-> Hub I64))
    (define (repair-price hub)
      (quotient (+ (- hub-health (Hub-health hub)) 1) 2))

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
    (: tasks (-> World (List Task)))
    (define (tasks world)
      (let loop ((pending (queued world)) (free (Hub-slots (World-hub world))) (listed (Nil)))
        (match pending
          ((Nil) (reverse listed))
          ((Cons (Pair owner work) rest)
           (let* ((supplied (supplied? world owner)) (active (and (> free 0) supplied)))
             (loop rest (if active (- free 1) free) (Cons (Task owner work supplied active) listed)))))))

    (: queued (-> World (List (Pair Owner Work))))
    (define (queued world)
      (insertion-sort (lambda (a b) (< (Work-order (Pair-second a)) (Work-order (Pair-second b))))
                      (append (match (Hub-work (World-hub world)) ((Some work) (list (Pair (OfHub) work))) ((None) (Nil)))
                              (filter-map (lambda (b) (match (Building-work b) ((Some work) (Some (Pair (OfBuilding b) work))) ((None) (None))))
                                          (World-buildings world)))))

    (: supplied? (-> World Owner Bool))
    (define (supplied? world owner)
      (match owner
        ((OfHub) #t)
        ((OfBuilding b) (if (built? b) (powered? world (Building-id b)) (in-reach? world (Building-kind b) (Building-cell b))))))

    ;; Active works progress, and finished ones raise their owner.
    (: work (-> World World))
    (define (work world)
      (fold-left (lambda (world task) (if (Task-active task) (progress world task) world)) world (tasks world)))

    (: progress (-> World Task World))
    (define (progress world task)
      (let ((work (Work-progress-set (Task-work task) (+ (Work-progress (Task-work task)) 1))))
        (if (> (remaining-work work) 0) (set-owner-work world (Task-owner task) (Some work)) (finish world (Task-owner task)))))

    ;; Finished work raises its owner: the hub gains a build slot, and a
    ;; building a level and its full health.
    (: finish (-> World Owner World))
    (define (finish world owner)
      (match owner
        ((OfHub) (let ((hub (World-hub world))) (World-hub-set world (Hub-work-set (Hub-slots-set hub (+ (Hub-slots hub) 1)) (None)))))
        ((OfBuilding b) (rewire (put-building world (Building-health-set (Building-work-set (Building-level-set b (+ (Building-level b) 1)) (None))
                                                                         (kind-health (Building-kind b))))))))

    ;; ---- Production ----

    ;; Every second each powered extractor draws its crystal's rate for each
    ;; of its levels, until the reserve runs out.
    (: produce (-> World World))
    (define (produce world)
      (if (= (remainder (World-tick world) 10) 0)
          (fold-left extract world (filter (lambda (b) (and (built? b) (extractor? b) (powered? world (Building-id b)))) (World-buildings world)))
          world))

    (: extractor? (-> Building Bool))
    (define (extractor? building)
      (match (Building-kind building)
        ((Extractor) #t)
        (_ #f)))

    (: extract (-> World Building World))
    (define (extract world extractor)
      (match (crystal-at world (Building-cell extractor))
        ((Some crystal)
         (let ((amount (min (Crystal-reserve crystal) (* (Crystal-rate crystal) (Building-level extractor)))))
           (earn (put-crystal world (Crystal-reserve-set crystal (- (Crystal-reserve crystal) amount))) amount)))
        ((None) world)))

    ;; ---- Lists ----

    (: filter-map (All (A B) (-> (-> A (Option B)) (List A) (List B))))
    (define (filter-map f items)
      (fold-right (lambda (item kept) (match (f item) ((Some value) (Cons value kept)) ((None) kept))) (Nil) items))

    ;; Stable, for the handful of queued works.
    (: insertion-sort (All (T) (-> (-> T T Bool) (List T) (List T))))
    (define (insertion-sort before? items)
      (fold-left (lambda (sorted item) (insert before? item sorted)) (Nil) items))

    (: insert (All (T) (-> (-> T T Bool) T (List T) (List T))))
    (define (insert before? item sorted)
      (match sorted
        ((Nil) (list item))
        ((Cons first rest) (if (before? item first) (Cons item sorted) (Cons first (insert before? item rest))))))

    ))
