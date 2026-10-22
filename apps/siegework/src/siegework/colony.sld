;; The colony's rules: the orders a player can give, the work that raises
;; sites and buildings, the workers who walk to it and labor there, and
;; the extractors that turn crystal into energy.
;;
;; `act` is the only way an order changes the world. It either rejects the
;; order with the reason, leaving the world as it was, or returns the world
;; with the order applied and paid for.
(define-library (siegework colony)
  (export
   Action
   Build
   Upgrade
   MakePortal
   Rush
   Cancel
   Scavenge
   Repair
   Train
   Resign
   Rejection
   rejection-text
   later?
   repair-price
   repair-duration
   scavenge-refund
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
   OfTraining
   tasks
   owner-work
   hub-works
   worker-count
   work
   toil
   produce)
  (import
   (lofi base)
   (lofi wire)
   (siegework grid)
   (siegework terrain)
   (siegework world)
   (siegework routes))
  (begin

    ;; ---- Orders ----

    ;; Orders name cells rather than ids, so a journal of them still means
    ;; the same places when it is replayed under changed rules.
    (enum Action
      (Build ((kind Kind) (cell Cell) (rush Bool)))
      (Upgrade ((cell Cell)))
      (MakePortal ((cell Cell)))
      (Rush ((cell Cell)))
      (Cancel ((cell Cell)))
      (Scavenge ((cell Cell)))
      (Repair)
      (Train)
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
      (HubFixed)
      (Unfinished)
      (Busy)
      (Idle)
      (MaximumLevel)
      (FullHealth)
      (NotPylon)
      (AlreadyPortal)
      (Crowded))

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
        ((HubFixed) "The hub has no upgrades; it trains workers.")
        ((Unfinished) "Finish building it first.")
        ((Busy) "It is already working.")
        ((Idle) "There is no work to change.")
        ((MaximumLevel) "It is fully upgraded.")
        ((FullHealth) "The hub is undamaged.")
        ((NotPylon) "Only a pylon can become a portal.")
        ((AlreadyPortal) "It is already a portal.")
        ((Crowded) "The colony has all twenty workers.")))

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
        ((Crowded) #t)
        (_ #f)))

    ;; Checks the order, then applies it. Every order needs a game in play.
    ;; Until the first extractor is ordered, an order that would otherwise
    ;; be accepted waits, so its rejection still tells whether it could
    ;; apply here at all.
    (: act (-> World Action (Result World Rejection)))
    (define (act world action)
      (if (playing? world)
          (match (apply-order world action)
            ((Ok next) (if (or (World-started world) (opening? action)) (Ok next) (Err (NotStarted))))
            ((Err rejection) (Err rejection)))
          (Err (Finished))))

    (: apply-order (-> World Action (Result World Rejection)))
    (define (apply-order world action)
      (match action
        ((Build kind cell rush) (build world kind cell rush))
        ((Upgrade cell) (with-owner world cell upgrade))
        ((MakePortal cell) (with-owner world cell make-portal))
        ((Rush cell) (with-owner world cell rush))
        ((Cancel cell) (with-owner world cell cancel))
        ((Scavenge cell) (with-owner world cell scavenge))
        ((Repair) (repair world))
        ((Train) (train world))
        ((Resign) (Ok (uncover (World-outcome-set world (Resigned)))))))

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

    ;; A site needs visible open ground that nothing occupies and a crystal
    ;; exactly when it is an extractor. Any site but a wall also needs a
    ;; powered building that can wire to it.
    (: build (-> World Kind Cell Bool (Result World Rejection)))
    (define (build world kind cell rush)
      (let ((extractor? (has-kind? (Some kind) (Extractor))) (crystal (crystal-at world cell)))
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
    ;; any other waits for a worker.
    (: place (-> World Kind Cell Bool (Result World Rejection)))
    (define (place world kind cell rush)
      (let* ((work (new-work world (Raising) (raise-cost kind 0) (raise-duration kind 0))) (ready (or rush (not (World-started world)))))
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
    ;; Walls hold no wires, so they are always in reach.
    (: in-reach? (-> World Kind Cell Bool))
    (define (in-reach? world kind cell)
      (or (has-kind? (Some kind) (Wall))
          (any? (lambda (node) (and (joinable? (Node-kind node) (Some kind))
                                    (wire-reaches? world (Node-cell node) (Node-reach node) cell (kind-reach kind 1))))
                (Network-powered (World-network world)))))

    ;; New work joins the end of the queue.
    (: new-work (-> World Labor I64 I64 Work))
    (define (new-work world labor cost duration)
      (Work (World-next-order world) labor cost duration 0))

    (: place-site (-> World Kind Cell Work Bool World))
    (define (place-site world kind cell work ready)
      (match (fresh-id world)
        ((Pair id world)
         (if ready
             (rewire (World-started-set (add-building world (Building id kind cell 1 (kind-health kind 1) (None) (None) #f)) #t))
             (structures-changed (World-next-order-set (add-building world (Building id kind cell 0 (kind-health kind 1) (Some work) (None) #f))
                                                       (+ (World-next-order world) 1)))))))

    (: add-building (-> World Building World))
    (define (add-building world building)
      (World-buildings-set world (append (World-buildings world) (list building))))

    ;; ---- Owners ----

    ;; What an order or a work belongs to: the hub's repair, a building as
    ;; found in the current world, or a worker in training, named by its
    ;; order. Upgrades, rushes, cancellations and scavenging name any cell
    ;; of the hub or of a building.
    (enum Owner
      (OfHub)
      (OfBuilding ((building Building)))
      (OfTraining ((order I64))))

    (: with-owner (-> World Cell (-> World Owner (Result World Rejection)) (Result World Rejection)))
    (define (with-owner world cell order)
      (cond ((hub-cell? (World-hub world) cell) (order world (OfHub)))
            (else (match (building-at world cell)
                    ((Some b) (order world (OfBuilding b)))
                    ((None) (Err (NothingThere)))))))

    ;; The hub's works, its repair and the workers in training, oldest
    ;; first.
    (: hub-works (-> World (List (Pair Owner Work))))
    (define (hub-works world)
      (let ((hub (World-hub world)))
        (insertion-sort (lambda (a b) (< (Work-order (Pair-second a)) (Work-order (Pair-second b))))
                        (append (match (Hub-work hub) ((Some work) (list (Pair (OfHub) work))) ((None) (Nil)))
                                (map (lambda (work) (Pair (OfTraining (Work-order work)) work)) (Hub-training hub))))))

    ;; The work an order on `owner` changes: a building's own, or at the hub
    ;; the newest or the oldest of its works.
    (: owner-work (-> World Owner Bool (Option (Pair Owner Work))))
    (define (owner-work world owner newest)
      (match owner
        ((OfBuilding b) (match (Building-work b) ((Some work) (Some (Pair owner work))) ((None) (None))))
        (_ (let ((works (hub-works world)))
             (cond ((null? works) (None))
                   (newest (last works))
                   (else (Some (list-ref works 0))))))))

    (: set-owner-work (-> World Owner (Option Work) World))
    (define (set-owner-work world owner work)
      (match owner
        ((OfHub) (World-hub-set world (Hub-work-set (World-hub world) work)))
        ((OfBuilding b) (put-building world (Building-work-set b work)))
        ((OfTraining order) (let ((hub (World-hub world)))
                              (World-hub-set world (Hub-training-set hub (filter-map (lambda (w) (if (= (Work-order w) order) work (Some w)))
                                                                                     (Hub-training hub))))))))

    ;; ---- Upgrades and portals ----

    ;; A building's upgrade adds a level.
    (: upgrade (-> World Owner (Result World Rejection)))
    (define (upgrade world owner)
      (match owner
        ((OfBuilding b) (let ((level (Building-level b)) (kind (Building-kind b)))
                          (cond ((not (built? b)) (Err (Unfinished)))
                                ((not (null-option? (Building-work b))) (Err (Busy)))
                                ((>= level maximum-level) (Err (MaximumLevel)))
                                (else (start-work world owner (new-work world (Raising) (raise-cost kind level) (raise-duration kind level)))))))
        (_ (Err (HubFixed)))))

    ;; Any built pylon may become a portal, at any level.
    (: make-portal (-> World Owner (Result World Rejection)))
    (define (make-portal world owner)
      (match owner
        ((OfBuilding b) (cond ((not (has-kind? (Some (Building-kind b)) (Pylon))) (Err (NotPylon)))
                              ((Building-portal b) (Err (AlreadyPortal)))
                              ((not (built? b)) (Err (Unfinished)))
                              ((not (null-option? (Building-work b))) (Err (Busy)))
                              (else (start-work world owner (new-work world (Linking) portal-cost portal-duration)))))
        (_ (Err (NotPylon)))))

    (: start-work (-> World Owner Work (Result World Rejection)))
    (define (start-work world owner work)
      (pay world (Work-cost work)
           (lambda (world) (structures-changed (World-next-order-set (set-owner-work world owner (Some work)) (+ (World-next-order world) 1))))))

    ;; ---- The hub's work ----

    ;; Repair restores the hub to full health, at one energy for each two
    ;; health it lacks, once a worker has labored there for two seconds.
    (: repair (-> World (Result World Rejection)))
    (define (repair world)
      (let ((hub (World-hub world)))
        (cond ((= (Hub-health hub) hub-health) (Err (FullHealth)))
              ((not (null-option? (Hub-work hub))) (Err (Busy)))
              (else (start-work world (OfHub) (new-work world (Mending) (repair-price hub) repair-duration))))))

    (: repair-price (-> Hub I64))
    (define (repair-price hub)
      (quotient (+ (- hub-health (Hub-health hub)) 1) 2))

    (: repair-duration I64)
    (define repair-duration 20)

    ;; The hub trains workers one after another, up to twenty in all.
    (: train (-> World (Result World Rejection)))
    (define (train world)
      (let ((hub (World-hub world)))
        (if (>= (worker-count world) maximum-workers)
            (Err (Crowded))
            (let ((work (new-work world (Training) worker-cost worker-duration)))
              (pay world worker-cost
                   (lambda (world)
                     (World-next-order-set (World-hub-set world (Hub-training-set hub (append (Hub-training hub) (list work)))) (+ (World-next-order world) 1))))))))

    ;; The workers standing and in training.
    (: worker-count (-> World I64))
    (define (worker-count world)
      (+ (length (World-workers world)) (length (Hub-training (World-hub world)))))

    ;; ---- Rushing and cancelling ----

    ;; Rushing at the hub finishes its oldest work.
    (: rush (-> World Owner (Result World Rejection)))
    (define (rush world owner)
      (match (owner-work world owner #f)
        ((Some (Pair owner work)) (pay world (rush-price work) (lambda (world) (finish world owner work))))
        ((None) (Err (Idle)))))

    ;; Cancelling a site removes it; cancelling an upgrade leaves the building
    ;; at its level. At the hub it cancels the newest work.
    (: cancel (-> World Owner (Result World Rejection)))
    (define (cancel world owner)
      (match (owner-work world owner #t)
        ((Some (Pair owner work)) (Ok (structures-changed (drop-work (spend world (- 0 (work-refund work))) owner))))
        ((None) (Err (Idle)))))

    (: drop-work (-> World Owner World))
    (define (drop-work world owner)
      (match owner
        ((OfBuilding b) (if (built? b) (set-owner-work world owner (None)) (remove-building world (Building-id b))))
        (_ (set-owner-work world owner (None)))))

    ;; ---- Scavenging ----

    ;; Scavenging removes an idle building and returns a fifth of everything
    ;; paid for it; removing a wall returns half.
    (: scavenge (-> World Owner (Result World Rejection)))
    (define (scavenge world owner)
      (match owner
        ((OfBuilding b) (cond ((not (built? b)) (Err (Unfinished)))
                              ((not (null-option? (Building-work b))) (Err (Busy)))
                              (else (Ok (remove-building (spend world (- 0 (scavenge-refund b))) (Building-id b))))))
        (_ (Err (HubOnly)))))

    (: scavenge-refund (-> Building I64))
    (define (scavenge-refund b)
      (quotient (invested b) (if (wall? b) 2 5)))

    ;; ---- Tasks ----

    ;; Each queued work with its owner, whether the owner is powered, and
    ;; whether the work progresses: the first worker in training does, and
    ;; any other work while a worker labors at its site.
    (struct Task
      ((owner Owner)
       (work Work)
       (supplied Bool)
       (active Bool)))

    ;; Works in the order they were given. A site counts as powered when a
    ;; powered building can wire to it; walls and the hub need no power.
    ;; An unpowered work keeps its progress and waits.
    (: tasks (-> World (List Task)))
    (define (tasks world)
      (let ((first-trainee (match (Hub-training (World-hub world)) ((Cons work _) (Work-order work)) ((Nil) -1))))
        (map (lambda (queued)
               (let* ((owner (Pair-first queued)) (supplied (supplied? world owner)))
                 (Task owner (Pair-second queued) supplied
                       (match owner
                         ((OfTraining order) (= order first-trainee))
                         (_ (and supplied (laboring? world owner)))))))
             (queued world))))

    (: queued (-> World (List (Pair Owner Work))))
    (define (queued world)
      (insertion-sort (lambda (a b) (< (Work-order (Pair-second a)) (Work-order (Pair-second b))))
                      (append (hub-works world)
                              (filter-map (lambda (b) (match (Building-work b) ((Some work) (Some (Pair (OfBuilding b) work))) ((None) (None))))
                                          (World-buildings world)))))

    (: supplied? (-> World Owner Bool))
    (define (supplied? world owner)
      (match owner
        ((OfBuilding b) (cond ((wall? b) #t)
                              ((built? b) (powered? world (Building-id b)))
                              (else (in-reach? world (Building-kind b) (Building-cell b)))))
        (_ #t)))

    ;; The id a worker's job names for an owner: the building's, or 0 for
    ;; the hub.
    (: owner-id (-> Owner I64))
    (define (owner-id owner)
      (match owner
        ((OfBuilding b) (Building-id b))
        (_ 0)))

    (: owner-cell (-> World Owner Cell))
    (define (owner-cell world owner)
      (match owner
        ((OfBuilding b) (Building-cell b))
        (_ (Hub-cell (World-hub world)))))

    ;; Whether a worker on this job stands at its site with no enemy beside
    ;; it.
    (: laboring? (-> World Owner Bool))
    (define (laboring? world owner)
      (any? (lambda (w) (and (match (Worker-job w) ((Some id) (= id (owner-id owner))) ((None) #f))
                             (at-site? world owner (Worker-cell w)) (not (enemy-beside? world (Worker-cell w)))))
            (World-workers world)))

    ;; A worker labors on a building from its cell or beside it, and on the
    ;; hub from its footprint or beside it.
    (: at-site? (-> World Owner Cell Bool))
    (define (at-site? world owner cell)
      (match owner
        ((OfBuilding b) (beside? cell (Building-cell b)))
        (_ (any? (lambda (n) (hub-cell? (World-hub world) n)) (Cons cell (neighbors cell))))))

    ;; ---- Work ----

    ;; The first worker in training and each work with a worker laboring at
    ;; it progress by a tick, and finished ones are done.
    (: work (-> World World))
    (define (work world)
      (fold-left (lambda (world task) (if (Task-active task) (progress world (Task-owner task) (Task-work task)) world)) world (tasks world)))

    (: progress (-> World Owner Work World))
    (define (progress world owner work)
      (let ((work (Work-progress-set work (+ (Work-progress work) 1))))
        (if (> (remaining-work work) 0) (set-owner-work world owner (Some work)) (finish world owner work))))

    ;; Finished work is done: a building gains a level and its full health
    ;; or becomes a portal, the hub is repaired, or a worker steps out of
    ;; the hub.
    (: finish (-> World Owner Work World))
    (define (finish world owner work)
      (match owner
        ((OfBuilding b) (rewire (put-building world (match (Work-labor work)
                                                      ((Linking) (Building-portal-set (Building-work-set b (None)) #t))
                                                      (_ (let ((level (+ (Building-level b) 1)))
                                                           (Building-health-set (Building-work-set (Building-level-set b level) (None))
                                                                                (kind-health (Building-kind b) level))))))))
        ((OfHub) (World-hub-set world (Hub-work-set (Hub-health-set (World-hub world) hub-health) (None))))
        ((OfTraining order) (add-worker (set-owner-work world owner (None))))))

    ;; ---- Workers ----

    ;; Each tick, jobs go to free workers, then workers walk. Jobs are taken
    ;; oldest first, each by the free worker nearest by walking route,
    ;; counting jumps between portals.
    (: toil (-> World World))
    (define (toil world)
      (walk-workers (assign (release world))))

    ;; A worker whose job is done, cancelled or destroyed is free again.
    (: release (-> World World))
    (define (release world)
      (let ((open (map (lambda (task) (owner-id (Task-owner task))) (labors world))))
        (World-workers-set world (map (lambda (w) (match (Worker-job w)
                                                    ((Some id) (if (member? id open) w (Worker-job-set w (None))))
                                                    ((None) w)))
                                      (World-workers world)))))

    ;; Works that need a worker at their site.
    (: labors (-> World (List Task)))
    (define (labors world)
      (filter (lambda (task) (needs-worker? (Work-labor (Task-work task)))) (tasks world)))

    ;; Powered works no worker has taken, oldest first.
    (: assign (-> World World))
    (define (assign world)
      (fold-left (lambda (world task)
                   (if (and (Task-supplied task) (not (taken? world (owner-id (Task-owner task)))))
                       (take-job world (Task-owner task))
                       world))
                 world (labors world)))

    (: taken? (-> World I64 Bool))
    (define (taken? world id)
      (any? (lambda (w) (match (Worker-job w) ((Some job) (= job id)) ((None) #f))) (World-workers world)))

    (: take-job (-> World Owner World))
    (define (take-job world owner)
      (let ((free (filter (lambda (w) (null-option? (Worker-job w))) (World-workers world))))
        (if (null? free)
            world
            (match (site-field world owner)
              ((Pair field world)
               (match (portal-field world)
                 ((Pair portals world)
                  (let ((best (fold-left (lambda (best w) (closer (route-length world field portals (Worker-cell w)) w best)) (None) free)))
                    (match best
                      ((Some (Pair length w)) (put-worker world (Worker-job-set w (Some (owner-id owner)))))
                      ((None) world))))))))))

    ;; The worker with the shorter route; ties go to the older, listed first.
    (: closer (-> I64 Worker (Option (Pair I64 Worker)) (Option (Pair I64 Worker))))
    (define (closer length w best)
      (cond ((< length 0) best)
            (else (match best
                    ((Some (Pair other _)) (if (< length other) (Some (Pair length w)) best))
                    ((None) (Some (Pair length w)))))))

    ;; Steps to a site, over the whole map, kept with the world's routes.
    (: site-field (-> World Owner (Pair Field World)))
    (define (site-field world owner)
      (match owner
        ((OfBuilding b) (route-field world (Building-cell b) (list (Building-cell b)) worker-mover))
        (_ (route-field world (Hub-cell (World-hub world)) (hub-cells (World-hub world)) worker-mover))))

    ;; The steps from `cell` to the site, walking all the way or to the
    ;; nearest portal and on from the best one; -1 if neither reaches it.
    (: route-length (-> World Field Field Cell I64))
    (define (route-length world field portals cell)
      (let ((direct (field-cost field cell)) (to-portal (field-cost portals cell)) (onward (best-portal world field)))
        (cond ((or (< to-portal 0) (< (Pair-first onward) 0)) direct)
              ((< direct 0) (+ to-portal (Pair-first onward)))
              (else (min direct (+ to-portal (Pair-first onward)))))))

    ;; The portal cell nearest the site, with its steps there, or -1.
    (: best-portal (-> World Field (Pair I64 Cell)))
    (define (best-portal world field)
      (fold-left (lambda (best cell)
                   (let ((cost (field-cost field cell)))
                     (if (and (>= cost 0) (or (< (Pair-first best) 0) (< cost (Pair-first best)))) (Pair cost cell) best)))
                 (Pair -1 (Hub-cell (World-hub world))) (portal-cells world)))

    ;; How a worker moves this turn.
    (enum Move
      (Stay)
      (Walk ((cell Cell)))
      (Jump ((cell Cell))))

    ;; On its period a worker with no enemy beside it moves: toward its
    ;; job until it is at the site, or else back to the nearest portal or
    ;; the hub.
    (: walk-workers (-> World World))
    (define (walk-workers world)
      (fold-left (lambda (world w)
                   (if (and (= (remainder (+ (World-tick world) (Worker-id w)) worker-period) 0) (not (enemy-beside? world (Worker-cell w))))
                       (walk world w)
                       world))
                 world (World-workers world)))

    (: walk (-> World Worker World))
    (define (walk world w)
      (match (next-move world w)
        ((Pair move world)
         (put-worker world (match move
                             ((Stay) (Worker-previous-set w (Worker-cell w)))
                             ((Walk cell) (Worker-cell-set (Worker-previous-set w (Worker-cell w)) cell))
                             ((Jump cell) (Worker-cell-set (Worker-previous-set w cell) cell)))))))

    (: next-move (-> World Worker (Pair Move World)))
    (define (next-move world w)
      (match (portal-field world)
        ((Pair portals world)
         (match (job-owner world w)
           ((Some owner) (if (at-site? world owner (Worker-cell w))
                             (Pair (Stay) world)
                             (match (site-field world owner) ((Pair field world) (Pair (toward world field portals (Worker-cell w)) world)))))
           ((None) (Pair (first-step world portals (Worker-cell w)) world))))))

    (: job-owner (-> World Worker (Option Owner)))
    (define (job-owner world w)
      (match (Worker-job w)
        ((Some id) (if (= id 0)
                       (Some (OfHub))
                       (match (building world id) ((Some b) (Some (OfBuilding b))) ((None) (None)))))
        ((None) (None))))

    ;; Standing on a portal or the hub, a worker jumps to the portal nearest
    ;; the site if that saves more than the two steps across the hub, so it
    ;; never jumps within the hub. Elsewhere it walks to the nearest portal
    ;; when going on from the best one is shorter than walking all the
    ;; way.
    (: toward (-> World Field Field Cell Move))
    (define (toward world field portals cell)
      (let ((direct (field-cost field cell)) (to-portal (field-cost portals cell)) (onward (best-portal world field)))
        (cond ((< (Pair-first onward) 0) (first-step world field cell))
              ((and (= to-portal 0) (or (< direct 0) (< (+ (Pair-first onward) 2) direct))) (Jump (Pair-second onward)))
              ((and (> to-portal 0) (or (< direct 0) (< (+ to-portal (Pair-first onward)) direct))) (first-step world portals cell))
              (else (first-step world field cell)))))

    ;; The first step downhill in a worker's field, in the fixed order of
    ;; neighbors.
    (: first-step (-> World Field Cell Move))
    (define (first-step world field cell)
      (match (downhill field (lambda (n) (enter-cost world worker-mover n)) cell)
        ((Cons next _) (Walk next))
        ((Nil) (Stay))))

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
