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

(define (report (world World)) (→ Unit) (! output-port)
  (let ((ledger (● world ledger)))
    (write-line (string-join (list (string-append "tick " (show (● world tick)))
                                   (string-append "energy " (show (● world energy)))
                                   (string-append "produced " (show (● ledger produced)))
                                   (string-append "spent " (show (● ledger spent)))
                                   (string-append "balanced "
                                                  (show (= (● world energy)
                                                           (- (+ starting-energy
                                                                 (● ledger produced))
                                                              (● ledger spent))))))
                             ", "))))

(define (reserve (world World) (cell Cell)) (→ I64)
  (match (crystal-at world cell)
    ((Some crystal) (● crystal reserve))
    ((None) 0)))

(define main
  (lambda ()
    (let ()
      (define world (new-world 3))
      (define starter (● (● world land) starter))
      (report world)
      (write-line (string-append "advancing before the first order changes nothing: "
                                 (show (= (● (run world 50) tick) 0))))
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
      (write-line (string-append "buildings " (show (length (● world buildings)))))
      (define damaged (World-hub-set world (Hub-health-set (● world hub) 421)))
      (define repaired (order damaged (Repair)))
      (write-line
       (string-append "repair restores the hub from 421 to " (show (● (● repaired hub) health))
                      " for " (show (- (● damaged energy) (● repaired energy))) " energy")))
    (unit)))
