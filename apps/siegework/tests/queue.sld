;; The hub works on as many orders as it has build slots, in the order
;; they were given. Rushing finishes work at once for four times the share
;; of its cost that remains, and cancelling returns the cost.
(import
 (snail core base)
 (snail core io)
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
    ((Err rejection)
     (begin (write-line (string-append "rejected: " (rejection-text rejection))) world))))

(: owner-text (-> World Owner String))
(define (owner-text world owner)
  (match owner
    ((OfHub) "hub slot")
    ((OfBuilding b)
     (string-append (kind-name (::kind b))
                    " "
                    (show (::x (::cell b)))
                    ","
                    (show (::y (::cell b)))))))

(: task-text (-> World Task String))
(define (task-text world task)
  (let ((work (::work task)))
    (string-append (owner-text world (::owner task))
                   " "
                   (show (::progress work))
                   "/"
                   (show (::duration work))
                   (if (::active task) " active" ""))))

(: report (-> World Unit ! console))
(define (report world)
  (write-line
   (string-append "tick " (show (::tick world)) ", energy " (show (::energy world))
                  ", slots " (show (::slots (::hub world))) ": "
                  (string-join (map (lambda (task) (task-text world task)) (tasks world)) "; "))))

(let ()
  (define world (new-world 3))
  (define world (order world (Build (Pylon) (Cell 39 46) #f)))
  (define world (order world (Build (Extractor) (Cell 39 43) #f)))
  (define world (order world (Upgrade (Cell 39 39))))
  (define world (order world (Build (Pylon) (Cell 39 46) #f)))
  (define world (order world (Build (Pylon) (Cell 35 39) #f)))
  (report world)
  (define world (run world 25))
  (define world (order world (Rush (Cell 39 39))))
  (report world)
  (define world (run world 25))
  (report world)
  (define world (run world 450))
  (define world (order world (Build (Pylon) (Cell 35 39) #f)))
  (define world (order world (Build (Pylon) (Cell 39 33) #f)))
  (report world)
  (define world (run world 10))
  (define world (order world (Rush (Cell 35 39))))
  (report world)
  (define world (order world (Cancel (Cell 39 33))))
  (report world)
  (define world (order world (Build (Pylon) (Cell 39 33) #t)))
  (report world))
