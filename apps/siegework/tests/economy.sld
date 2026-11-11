;; A scripted colony on seed 3, a meadow: an extractor on the starter crystal, ready
;; at once as every colony's first is, then its upgrade and a scavenged
;; pylon. Energy always equals the starting
;; energy plus what was produced minus what was spent, net of refunds.
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

(define (order (world World) (action Action)) (→ World)
  (match (act world action)
    ((Ok world) world)
    ((Err rejection) (panic (rejection-text rejection)))))

(define (report (world World)) (→ Unit) (! console)
  (let ((ledger (::ledger world)))
    (write-line (string-join (list (string-append "tick " (show (::tick world)))
                                   (string-append "energy " (show (::energy world)))
                                   (string-append "produced " (show (::produced ledger)))
                                   (string-append "spent " (show (::spent ledger)))
                                   (string-append "balanced "
                                                  (show (= (::energy world)
                                                           (- (+ starting-energy
                                                                 (::produced ledger))
                                                              (::spent ledger))))))
                             ", "))))

(define (reserve (world World) (cell Cell)) (→ I64)
  (match (crystal-at world cell)
    ((Some crystal) (::reserve crystal))
    ((None) 0)))

(let ()
  (define world (new-world 3))
  (define starter (::starter (::land world)))
  (report world)
  (write-line (string-append "advancing before the first order changes nothing: "
                             (show (= (::tick (run world 50)) 0))))
  (define world (order world (Build (Extractor) starter #f)))
  (write-line (string-append "the first extractor is ready at once: "
                             (show (match (building-at world starter)
                                     ((Some b) (built? b))
                                     ((None) #f)))))
  (define world (run world 100))
  (report world)
  (write-line (string-append "starter reserve " (show (reserve world starter))))
  (define world (order world (Upgrade starter)))
  (define world (run world 100))
  (report world)
  (define world (run world 100))
  (report world)
  (define world (order world (Build (Pylon) (Cell 39 46) #f)))
  (define world (run world 60))
  (report world)
  (define world (order world (Scavenge (Cell 39 46))))
  (report world)
  (write-line (string-append "buildings " (show (length (::buildings world)))))
  (define damaged (World-hub-set world (Hub-health-set (::hub world) 421)))
  (define repaired (order damaged (Repair)))
  (write-line
   (string-append "repair restores the hub from 421 to " (show (::health (::hub repaired)))
                  " for " (show (- (::energy damaged) (::energy repaired))) " energy")))
