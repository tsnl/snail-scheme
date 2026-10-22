;; Work waits for a worker, oldest first, and the hub trains workers in the
;; same queue. Rushing finishes work at once for four times the share of
;; its cost that remains, and cancelling returns the cost: at the hub,
;; rushing takes its oldest work and cancelling its newest.
(import
 (lofi base)
 (lofi io)
 (siegework grid)
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

(: owner-text (-> World Owner String))
(define (owner-text world owner)
  (match owner
    ((OfHub) "hub repair")
    ((OfTraining _) "worker")
    ((OfBuilding b) (string-append (kind-name (Building-kind b)) " " (show (Cell-x (Building-cell b))) "," (show (Cell-y (Building-cell b)))))))

(: task-text (-> World Task String))
(define (task-text world task)
  (let ((work (Task-work task)))
    (string-append (owner-text world (Task-owner task)) " " (show (Work-progress work)) "/" (show (Work-duration work))
                   (if (Task-active task) " active" ""))))

(: report (-> World Unit ! console))
(define (report world)
  (write-line (string-append "tick " (show (World-tick world)) ", energy " (show (World-energy world))
                             ", workers " (show (length (World-workers world))) ": "
                             (string-join (map (lambda (task) (task-text world task)) (tasks world)) "; "))))

(let ()
  (define world (new-world 3))
  (define world (order world (Build (Pylon) (Cell 39 46) #f)))
  (define world (order world (Build (Extractor) (Cell 39 43) #f)))
  (define world (order world (Train)))
  (define world (order world (Train)))
  (define world (order world (Build (Pylon) (Cell 39 46) #f)))
  (define world (order world (Build (Pylon) (Cell 35 39) #f)))
  (define world (order world (Build (Pylon) (Cell 39 33) #f)))
  (report world)
  (define world (run world 25))
  (report world)
  (define world (order world (Rush (Cell 39 39))))
  (define world (order world (Cancel (Cell 39 39))))
  (report world)
  (define world (run world 40))
  (report world)
  (define world (run world 400))
  (define world (order world (Build (Pylon) (Cell 35 41) #f)))
  (define world (order world (Build (Pylon) (Cell 39 31) #f)))
  (report world)
  (define world (run world 10))
  (define world (order world (Rush (Cell 35 41))))
  (report world)
  (define world (order world (Cancel (Cell 39 31))))
  (report world)
  (define world (order world (Build (Pylon) (Cell 39 31) #t)))
  (report world))
