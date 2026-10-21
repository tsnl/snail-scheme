;; Power on seed 1. The northern crystal is out of the hub's reach, so its
;; extractor is wired through a pylon. Scavenging that pylon cuts the
;; extractor off: it stops yielding and stops lighting the map. Building the
;; pylon again restores both. Wires run along the shortest links that
;; connect everything, so a second pylon nearer the extractor takes over
;; its wire, and scavenging that one rewires the extractor through the
;; first.
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

(: visible-count (-> World I64))
(define (visible-count world)
  (vector-fold (lambda (n seen) (if seen (+ n 1) n)) 0 (World-visible world)))

(: wire-text (-> Wire String))
(define (wire-text wire)
  (string-append (cell-text (Node-cell (Wire-from wire))) "-" (cell-text (Node-cell (Wire-to wire)))))

(: cell-text (-> Cell String))
(define (cell-text cell)
  (string-append (show (Cell-x cell)) "," (show (Cell-y cell))))

(: report-wires (-> World Unit ! console))
(define (report-wires world)
  (write-line (string-append "wires " (string-join (map wire-text (Network-wires (World-network world))) " "))))

(: report (-> World Unit ! console))
(define (report world)
  (write-line (string-append "tick " (show (World-tick world)) ", produced " (show (Ledger-produced (World-ledger world)))
                             ", wires " (show (length (Network-wires (World-network world))))
                             ", visible " (show (visible-count world)) ": "
                             (string-join (map (lambda (b) (string-append (kind-name (Building-kind b)) " " (show (Cell-x (Building-cell b))) "," (show (Cell-y (Building-cell b)))
                                                                          (cond ((not (built? b)) " unfinished") ((powered? world (Building-id b)) " powered") (else " unpowered"))))
                                               (World-buildings world))
                                          "; "))))

(let ()
  (define north (Cell 39 31))
  (define relay (Cell 38 36))
  (define world (new-world 1))
  (define world (order world (Build (Extractor) north #f)))
  (define world (order world (Build (Extractor) (Cell 42 38) #f)))
  (define world (order world (Build (Pylon) relay #f)))
  (define world (run world 250))
  (define world (order world (Build (Extractor) north #f)))
  (define world (run world 150))
  (report world)
  (define world (run world 50))
  (report world)
  (define world (order world (Scavenge relay)))
  (report world)
  (define world (run world 50))
  (report world)
  (define world (order world (Build (Pylon) relay #t)))
  (define world (run world 50))
  (report world)
  (define world (run world 50))
  (report world)
  (report-wires world)
  (define world (run (order world (Build (Pylon) (Cell 42 33) #f)) 30))
  (report-wires world)
  (define world (order world (Scavenge (Cell 42 33))))
  (report world)
  (report-wires world))
