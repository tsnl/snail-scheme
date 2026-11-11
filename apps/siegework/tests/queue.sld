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

(define (run (world World) (ticks I64)) (→ World)
  (if (= ticks 0) world (run (advance world) (- ticks 1))))

(define (order (world World) (action Action)) (→ World) (! console)
  (match (act world action)
    ((Ok world) world)
    ((Err rejection)
     (begin (write-line (string-append "rejected: " (rejection-text rejection))) world))))

(define (owner-text (world World) (owner Owner)) (→ String)
  (match owner
    ((OfHub) "hub slot")
    ((OfBuilding b)
     (string-append (kind-name (::kind b))
                    " "
                    (show (::x (::cell b)))
                    ","
                    (show (::y (::cell b)))))))

(define (task-text (world World) (task Task)) (→ String)
  (let ((work (::work task)))
    (string-append (owner-text world (::owner task))
                   " "
                   (show (::progress work))
                   "/"
                   (show (::duration work))
                   (if (::active task) " active" ""))))

(define (report (world World)) (→ Unit) (! console)
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
