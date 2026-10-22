;; Workers, portals and walls on seed 3, a meadow with open ground east of
;; the hub:
;;
;; - the three starting workers take jobs oldest first, each going to the
;;   free worker nearest by walking route, and labor at the site;
;; - a worker that falls leaves its site's progress for the next;
;; - the hub trains workers up to twenty;
;; - a worker jumps from the hub to a powered portal near its job;
;; - a pylon beyond the hub's reach draws power along a chain of walls,
;;   and loses it when a wall in the chain is removed for half its cost.
(import
 (lofi base)
 (lofi io)
 (siegework grid)
 (only (siegework terrain) Land-starter)
 (siegework world)
 (siegework colony)
 (siegework simulation))

(: run (-> World I64 World))
(define (run world ticks)
  (if (= ticks 0) world (run (advance world) (- ticks 1))))

(: order (-> World Action World ! console))
(define (order world action)
  (match (act world action)
    ((Ok world) world)
    ((Err rejection) (begin (write-line (string-append "rejected: " (rejection-text rejection))) world))))

(: cell-text (-> Cell String))
(define (cell-text cell)
  (string-append (show (Cell-x cell)) "," (show (Cell-y cell))))

(: worker-text (-> World Worker String))
(define (worker-text world w)
  (string-append "worker " (show (Worker-id w)) " at " (cell-text (Worker-cell w))
                 (match (Worker-job w)
                   ((Some 0) " on the hub")
                   ((Some id) (match (building world id) ((Some b) (string-append " on the " (kind-name (Building-kind b)) " at " (cell-text (Building-cell b)))) ((None) "")))
                   ((None) " idle"))))

(: task-text (-> Task String))
(define (task-text task)
  (let ((work (Task-work task)))
    (string-append (match (Task-owner task)
                     ((OfHub) "hub repair")
                     ((OfTraining _) "worker")
                     ((OfBuilding b) (string-append (kind-name (Building-kind b)) " " (cell-text (Building-cell b)))))
                   " " (show (Work-progress work)) "/" (show (Work-duration work)) (if (Task-active task) " active" ""))))

(: report (-> World Unit ! console))
(define (report world)
  (write-line (string-append "tick " (show (World-tick world)) ", energy " (show (World-energy world)) ": "
                             (string-join (map (lambda (task) (task-text task)) (tasks world)) "; ")))
  (for-each (lambda (w) (write-line (string-append "  " (worker-text world w)))) (World-workers world)))

(: power-text (-> World Cell String))
(define (power-text world cell)
  (match (building-at world cell)
    ((Some b) (if (powered? world (Building-id b)) "powered" "unpowered"))
    ((None) "gone")))

;; Jobs, workers' deaths and training.
(let ()
  (define world (new-world 3))
  (define world (order world (Build (Extractor) (Land-starter (World-land world)) #f)))
  (define world (order world (Build (Pylon) (Cell 46 39) #f)))
  (define world (order world (Build (Pylon) (Cell 39 33) #f)))
  (define world (order world (Build (Wall) (Cell 39 35) #f)))
  (define world (order world (Build (Wall) (Cell 40 35) #f)))
  (report world)
  (define world (run world 20))
  (report world)
  (define world (run world 20))
  (report world)
  ;; The worker on the eastern pylon falls; another finishes it.
  (define east (find (lambda (w) (match (Worker-job w) ((Some id) (match (building world id) ((Some b) (= (Cell-x (Building-cell b)) 46)) ((None) #f))) ((None) #f)))
                     (World-workers world)))
  (define world (match east ((Some w) (put-worker world (Worker-health-set w 0))) ((None) world)))
  (define world (run world 1))
  (write-line "the worker on the eastern pylon falls:")
  (report world)
  (define world (run world 20))
  (report world)
  (define world (run world 60))
  (report world)
  (define world (earn world 1000))
  (define world (fold-left (lambda (world i) (match (act world (Train)) ((Ok world) world) ((Err _) world))) world (iota 30)))
  (write-line (string-append "workers ordered up to " (show (worker-count world)) ", training " (show (length (Hub-training (World-hub world))))))
  (define world (order world (Train)))
  (define world (run world 300))
  (write-line (string-append "tick " (show (World-tick world)) ": workers " (show (length (World-workers world))) ", training " (show (length (Hub-training (World-hub world)))))))

;; Portals: a pylon east of the hub becomes a portal; a worker jumps there
;; on its way to a site farther east.
(: path-text (-> World I64 I64 (List String)))
(define (path-text world id ticks)
  (if (= ticks 0)
      (Nil)
      (let ((next (advance world)))
        (match (worker next id)
          ((Some w) (if (cell=? (Worker-cell w) (match (worker world id) ((Some old) (Worker-cell old)) ((None) (Worker-cell w))))
                        (path-text next id (- ticks 1))
                        (Cons (string-append (show (World-tick next)) ":" (cell-text (Worker-cell w))) (path-text next id (- ticks 1)))))
          ((None) (Nil))))))

(let ()
  (define world (new-world 3))
  (define world (order world (Build (Extractor) (Land-starter (World-land world)) #f)))
  (define world (earn world 1000))
  (define world (order world (Build (Pylon) (Cell 46 39) #t)))
  (define world (order world (MakePortal (Cell 46 39))))
  (define world (order world (Rush (Cell 46 39))))
  (write-line (string-append "the pylon at 46,39 is a portal: " (show (match (building-at world (Cell 46 39)) ((Some b) (portal? b)) ((None) #f)))))
  (define world (order world (Build (Turret) (Cell 51 39) #f)))
  (write-line (string-append "a worker's moves to the turret at 51,39: " (string-join (path-text world 1 60) " "))))

;; Walls carry power: a pylon wired only through a chain of walls.
(let ()
  (define world (new-world 3))
  (define world (order world (Build (Extractor) (Land-starter (World-land world)) #f)))
  (define world (earn world 2000))
  (define world (order world (Build (Pylon) (Cell 46 39) #t)))
  (define world (order world (Build (Pylon) (Cell 52 40) #t)))
  (define world (fold-left (lambda (world x) (order world (Build (Wall) (Cell x 39) #t))) world (map (lambda (i) (+ 47 i)) (iota 10))))
  (define world (order world (Build (Pylon) (Cell 59 40) #t)))
  (define world (order world (Scavenge (Cell 46 39))))
  (define world (order world (Scavenge (Cell 52 40))))
  (write-line (string-append "with the other pylons gone, the pylon at 59,40 is " (power-text world (Cell 59 40))))
  (define before (World-energy world))
  (define world (order world (Scavenge (Cell 50 39))))
  (write-line (string-append "removing the wall at 50,39 refunds " (show (- (World-energy world) before)) ", and the pylon is " (power-text world (Cell 59 40))))
  (define world (order world (Upgrade (Cell 49 39))))
  (define world (run world 80))
  (write-line (string-append "the wall at 49,39 upgraded by a worker: level " (show (match (building-at world (Cell 49 39)) ((Some b) (Building-level b)) ((None) 0)))
                             ", health " (show (match (building-at world (Cell 49 39)) ((Some b) (Building-health b)) ((None) 0))))))
