;; A scripted colony on seed 3, a meadow: an extractor on the starter crystal, ready
;; at once as every colony's first is, then its upgrade and a scavenged
;; pylon. Energy always equals the starting
;; energy plus what was produced minus what was spent, net of refunds.
(import
 (snail core base)
 (snail core io)
 (siegework grid)
 (only (siegework terrain) Land-starter)
 (siegework world)
 (siegework colony)
 (siegework simulation))

(: run (-> World I64 World))
(define (run world ticks)
  (if (= ticks 0) world (run (advance world) (- ticks 1))))

(: order (-> World Action World))
(define (order world action)
  (match (act world action)
    ((Ok world) world)
    ((Err rejection) (panic (rejection-text rejection)))))

(: report (-> World Unit ! console))
(define (report world)
  (let ((ledger (World-ledger world)))
    (write-line (string-join (list (string-append "tick " (show (World-tick world)))
                                   (string-append "energy " (show (World-energy world)))
                                   (string-append "produced " (show (Ledger-produced ledger)))
                                   (string-append "spent " (show (Ledger-spent ledger)))
                                   (string-append "balanced "
                                                  (show (= (World-energy world)
                                                           (- (+ starting-energy
                                                                 (Ledger-produced ledger))
                                                              (Ledger-spent ledger))))))
                             ", "))))

(: reserve (-> World Cell I64))
(define (reserve world cell)
  (match (crystal-at world cell)
    ((Some crystal) (Crystal-reserve crystal))
    ((None) 0)))

(let ()
  (define world (new-world 3))
  (define starter (Land-starter (World-land world)))
  (report world)
  (write-line (string-append "advancing before the first order changes nothing: "
                             (show (= (World-tick (run world 50)) 0))))
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
  (write-line (string-append "buildings " (show (length (World-buildings world)))))
  (define damaged (World-hub-set world (Hub-health-set (World-hub world) 421)))
  (define repaired (order damaged (Repair)))
  (write-line
   (string-append "repair restores the hub from 421 to " (show (Hub-health (World-hub repaired)))
                  " for " (show (- (World-energy damaged) (World-energy repaired))) " energy")))
