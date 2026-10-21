;; The hub works on as many orders as it has build slots, in the order
;; they were given. Rushing doubles the rate of what remains for four times
;; its share of the cost, and cancelling returns the cost and the unused
;; part of a rush.
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
    ((OfHub) "hub slot")
    ((OfBuilding b) (string-append (kind-name (Building-kind b)) " " (show (Cell-x (Building-cell b))) "," (show (Cell-y (Building-cell b)))))))

(: task-text (-> World Task String))
(define (task-text world task)
  (let ((work (Task-work task)))
    (string-append (owner-text world (Task-owner task)) " " (show (Work-progress work)) "/" (show (Work-duration work))
                   (if (Work-rushed work) " rushed" "") (if (Task-active task) " active" ""))))

(: report (-> World Unit ! console))
(define (report world)
  (write-line (string-append "tick " (show (World-tick world)) ", energy " (show (World-energy world))
                             ", slots " (show (Hub-slots (World-hub world))) ": "
                             (string-join (map (lambda (task) (task-text world task)) (tasks world)) "; "))))

(let ()
  (define world (new-world 1))
  (define world (order world (Build (Pylon) (Cell 38 46) #f)))
  (define world (order world (Build (Extractor) (Cell 42 38) #f)))
  (define world (order world (Upgrade (Cell 38 40))))
  (define world (order world (Build (Pylon) (Cell 38 46) #f)))
  (define world (order world (Build (Pylon) (Cell 34 40) #f)))
  (report world)
  (define world (run world 200))
  (report world)
  (define world (order world (Rush (Cell 38 40))))
  (define world (run world 300))
  (report world)
  (define world (order world (Build (Pylon) (Cell 34 40) #f)))
  (report world)
  (define world (run world 75))
  (define world (order world (Rush (Cell 38 46))))
  (report world)
  (define world (run world 38))
  (report world)
  (define world (order world (Cancel (Cell 34 40))))
  (report world)
  (define world (order world (Build (Pylon) (Cell 34 40) #t)))
  (define world (order world (Cancel (Cell 38 46))))
  (report world))
