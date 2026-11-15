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

(define (order (world World) (action Action)) (→ World) (! output-port)
  (match (act world action)
    ((Ok world) world)
    ((Err rejection)
     (begin (write-line (string-append "rejected: " (rejection-text rejection))) world))))

(define (owner-text (world World) (owner Owner)) (→ String)
  (match owner
    ((OfHub) "hub slot")
    ((OfBuilding b)
     (string-append (kind-name (● b kind))
                    " "
                    (show (● (● b cell) x))
                    ","
                    (show (● (● b cell) y))))))

(define (task-text (world World) (task Task)) (→ String)
  (let ((work (● task work)))
    (string-append (owner-text world (● task owner))
                   " "
                   (show (● work progress))
                   "/"
                   (show (● work duration))
                   (if (● task active) " active" ""))))

(define (report (world World)) (→ Unit) (! output-port)
  (write-line
   (string-append "tick " (show (● world tick)) ", energy " (show (● world energy))
                  ", slots " (show (● (● world hub) slots)) ": "
                  (string-join (map (lambda (task) (task-text world task)) (tasks world)) "; "))))

(define (main) (→ Unit) (! output-port)

  (let ()
    (define world (new-world 3))
    (define world (order world (Build (Pylon) (new Cell (x 39) (y 46)) #f)))
    (define world (order world (Build (Extractor) (new Cell (x 39) (y 43)) #f)))
    (define world (order world (Upgrade (new Cell (x 39) (y 39)))))
    (define world (order world (Build (Pylon) (new Cell (x 39) (y 46)) #f)))
    (define world (order world (Build (Pylon) (new Cell (x 35) (y 39)) #f)))
    (report world)
    (define world (run world 25))
    (define world (order world (Rush (new Cell (x 39) (y 39)))))
    (report world)
    (define world (run world 25))
    (report world)
    (define world (run world 450))
    (define world (order world (Build (Pylon) (new Cell (x 35) (y 39)) #f)))
    (define world (order world (Build (Pylon) (new Cell (x 39) (y 33)) #f)))
    (report world)
    (define world (run world 10))
    (define world (order world (Rush (new Cell (x 35) (y 39)))))
    (report world)
    (define world (order world (Cancel (new Cell (x 39) (y 33)))))
    (report world)
    (define world (order world (Build (Pylon) (new Cell (x 39) (y 33)) #t)))
    (report world))
  (unit))
