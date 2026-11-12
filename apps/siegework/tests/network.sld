;; Power on seed 3, a meadow. The crystal west across the lake is out of
;; the hub's reach, so its extractor is wired through a pylon; wires cross
;; water. Scavenging that pylon cuts the
;; extractor off: it stops yielding and stops lighting the map. Building the
;; pylon again restores both. Wires run along the shortest links that
;; connect everything, so a second pylon nearer the extractor takes over
;; its wire, and scavenging that one rewires the extractor through the
;; first.
(import
 (snail core base)
 (snail core io)
 (siegework grid)
 (only (siegework terrain))
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

(define (visible-count (world World)) (→ I64)
  (vector-fold (lambda (n seen) (if seen (+ n 1) n)) 0 (● world visible)))

(define (wire-text (wire Wire)) (→ String)
  (string-append (cell-text (● (● wire from) cell))
                 "-"
                 (cell-text (● (● wire to) cell))))

(define (cell-text (cell Cell)) (→ String)
  (string-append (show (● cell x)) "," (show (● cell y))))

(define (report-wires (world World)) (→ Unit) (! output-port)
  (write-line (string-append "wires "
                             (string-join (map wire-text (● (● world network) wires))
                                          " "))))

(define (report (world World)) (→ Unit) (! output-port)
  (write-line (string-append "tick "
                             (show (● world tick))
                             ", produced "
                             (show (● (● world ledger) produced))
                             ", wires " (show (length (● (● world network) wires)))
                             ", visible " (show (visible-count world)) ": "
                             (string-join (map (lambda (b)
                                                 (string-append (kind-name (● b kind))
                                                                " "
                                                                (show (● (● b cell) x))
                                                                ","
                                                                (show (● (● b cell) y))
                                                                (cond
                                                                 ((not (built? b)) " unfinished")
                                                                 ((powered? world (● b id))
                                                                  " powered")
                                                                 (else " unpowered"))))
                                               (● world buildings))
                                          "; "))))

(let ()
  (define west (Cell 30 35))
  (define relay (Cell 30 39))
  (define world (new-world 3))
  (define world (order world (Build (Extractor) west #f)))
  (define world (order world (Build (Extractor) (● (● world land) starter) #f)))
  (define world (order world (Build (Pylon) relay #f)))
  (define world (run world 250))
  (define world (order world (Build (Extractor) west #f)))
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
  (define world (run (order world (Build (Pylon) (Cell 29 36) #f)) 30))
  (report-wires world)
  (define world (order world (Scavenge (Cell 29 36))))
  (report world)
  (report-wires world))
