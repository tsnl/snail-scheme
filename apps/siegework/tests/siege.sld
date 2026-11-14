;; The nests' schedule, then two colonies on seed 1: one leaves its hub
;; undefended, the other keeps adding turrets around it and widens its
;; build slots. Last, an enemy between two turrets holds to one of them,
;; and each turret's guns stay on its last shot.
(import
 (snail core base)
 (snail core io)
 (siegework grid)
 (only (siegework terrain))
 (siegework world)
 (siegework colony)
 (siegework siege)
 (siegework simulation))

(define (run (world World) (ticks I64)) (→ World)
  (if (or (= ticks 0) (not (playing? world))) world (run (advance world) (- ticks 1))))

(define (try (world World) (action Action)) (→ World)
  (match (act world action)
    ((Ok world) world)
    ((Err _) world)))

(define (outcome-text (outcome Outcome)) (→ String)
  (match outcome
    ((Playing) "playing")
    ((Won) "won")
    ((Lost) "lost")
    ((Resigned) "resigned")))

(define (report (name String) (world World)) (→ Unit) (! output-port)
  (write-line (string-append name
                             ": tick "
                             (show (● world tick))
                             ", buildings "
                             (show (length (● world buildings)))
                             ", hub "
                             (show (● (● world hub) health))
                             ", enemies "
                             (show (length (● world enemies)))
                             ", kills "
                             (show (● (● world ledger) kills))
                             ", lost "
                             (show (● (● world ledger) lost))
                             ", opened rock "
                             (show (vector-fold (lambda (n open) (if open (+ n 1) n))
                                                0
                                                (● world opened)))
                             ", " (outcome-text (● world outcome)))))

(define (attack-text (tick I64)) (→ String)
  (string-append (show tick)
                 " "
                 (match (attack-kind tick) ((Regular) "wave") ((Raid) "raid") ((Heavy) "boss"))
                 " of "
                 (show (attack-size tick))))

(define (offset (world World) (dx I64) (dy I64)) (→ Cell)
  (let ((hub (● (● world hub) cell)))
    (new Cell (x (+ (● hub x) dx)) (y (+ (● hub y) dy)))))

(define (started (world World)) (→ World)
  (try world (Build (Extractor) (● (● world land) starter) #f)))

(define (reinforce (world World)) (→ World)
  (try (fold-left (lambda (world d)
                    (try world (Build (Turret) (offset world (● d first) (● d second)) #f)))
                  world
                  (list (new Pair (first -2) (second 0))
                        (new Pair (first 0) (second 2))
                        (new Pair (first 2) (second 0))
                        (new Pair (first 0) (second -2))
                        (new Pair (first -2) (second 2))
                        (new Pair (first 2) (second -2))
                        (new Pair (first 2) (second 2))
                        (new Pair (first -2) (second -2))))
       (Upgrade (offset world 0 0))))

(define (defend (world World) (ticks I64)) (→ World)
  (if (or (<= ticks 0) (not (playing? world)))
      world
      (defend (run (reinforce world) 100) (- ticks 100))))





;; Turrets three cells west and east of the hub flank a sturdy enemy to
;; the north. Both hit it, but it turns only on the first and keeps after
;; that one.
(define (flanked (world World)) (→ World)
  (let ((world (run (try (try world (Build (Turret) (offset world -3 0) #f))
                         (Build (Turret) (offset world 3 0) #f))
                    100)))
    (World-enemies-set world
                       (list (new Enemy (id 999)
                                  (behavior (Minion))
                                  (rank 0)
                                  (burrower #f)
                                  (cell (offset world 0 4))
                                  (previous (offset world 0 4))
                                  (health 2000)
                                  (maximum 2000)
                                  (raid (None))
                                  (aggro (None)))))))

(define (aggro-text (world World)) (→ String)
  (match (find (lambda (e) (= (● e id) 999)) (● world enemies))
    ((Some enemy)
     (match (● enemy aggro)
       ((Some id) (string-append "building " (show id)))
       ((None) "nothing")))
    ((None) "gone")))

(define (watch (world World) (ticks I64)) (→ Unit) (! output-port)
  (if (> ticks 0)
      (let ((next (advance world)))
        (for-each (lambda (shot)
                    (write-line (string-append "tick "
                                               (show (● next tick))
                                               ": the turret at x "
                                               (show (● (● shot from) x))
                                               " fires; the enemy has turned on "
                                               (aggro-text next))))
                  (filter (lambda (shot) (= (● shot tick) (● next tick)))
                          (● next shots)))
        (watch next (- ticks 1)))
      (begin
        (write-line (string-append "at tick "
                                   (show (● world tick))
                                   " the enemy has turned on "
                                   (aggro-text world)))
        (write-line (string-append "the guns stay on each turret's last shot: "
                                   (string-join (map aim-text (● world buildings)) ", "))))))

(define (aim-text (b Building)) (→ String)
  (string-append (kind-name (● b kind)) " at x " (show (● (● b cell) x)) " "
                 (match (● b aim)
                   ((Some cell)
                    (string-append "aims at " (show (● cell x)) "," (show (● cell y))))
                   ((None) "has not fired"))))

(define (main) (→ Unit) (! output-port)
  (define lost (run (started (new-world 1)) 6000))
  (define defended (defend (started (new-world 1)) 1000))
  (write-line
   (string-append "attacks: " (string-join (map attack-text (let loop ((tick 0) (found (Nil)))
                                                              (if (= (length found) 12)
                                                                  (reverse found)
                                                                  (let ((next
                                                                         (next-attack-tick tick)))
                                                                    (loop next
                                                                          (Cons next found))))))
                                           ", ")))
  (write-line
   (string-append "next attack after tick 5000: " (attack-text (next-attack-tick 5000))))
  (report "undefended" lost)
  (write-line (string-append "the lost colony's whole map is uncovered: "
                             (show (vector-fold (lambda (all seen) (and all seen))
                                                #t
                                                (● lost explored)))))
  (report "defended" defended)
  (report "defended" (defend defended 2000))
  (watch (flanked (started (new-world 1))) 40)
  (unit))
