;; A colony rebuilt from its seed and journal is the colony that was
;; played. A defended game on seed 3 is played through `command`, which
;; journals each accepted order; replaying the journal must reproduce the
;; world exactly, even with a rejected order slipped in, and the journal
;; must survive its wire encoding.
(import
 (lofi base)
 (lofi io)
 (lofi wire)
 (siegework grid)
 (only (siegework terrain) Land-starter)
 (siegework world)
 (siegework colony)
 (siegework simulation))

;; A game in progress: the world and its journal, newest entry first.
(struct Played
  ((world World)
   (journal (List Entry))))

(: give (-> Played Action Played))
(define (give played action)
  (match (command (Played-world played) action)
    ((Ok (Pair world entry)) (Played world (Cons entry (Played-journal played))))
    ((Err _) played)))

(: run (-> Played I64 Played))
(define (run played ticks)
  (if (= ticks 0) played (run (Played-world-set played (advance (Played-world played))) (- ticks 1))))

(: offset (-> World I64 I64 Cell))
(define (offset world dx dy)
  (let ((hub (Hub-cell (World-hub world))))
    (Cell (+ (Cell-x hub) dx) (+ (Cell-y hub) dy))))

(: reinforce (-> Played Played))
(define (reinforce played)
  (let ((world (Played-world played)))
    (give (fold-left (lambda (played d) (give played (Build (Turret) (offset world (Pair-first d) (Pair-second d)) #f)))
                     (give played (Build (Pylon) (offset world 3 0) #f))
                     (list (Pair -2 0) (Pair 0 2) (Pair 2 0) (Pair 0 -2) (Pair -2 2) (Pair 2 -2)))
          (Train))))

(: play (-> Played I64 Played))
(define (play played rounds)
  (if (= rounds 0) played (play (run (reinforce played) 100) (- rounds 1))))

;; Everything the rules decide, as text.
(: fingerprint (-> World String))
(define (fingerprint world)
  (string-join (list (show (World-tick world)) (show (World-energy world)) (show (Ledger-produced (World-ledger world)))
                     (show (Ledger-spent (World-ledger world))) (show (Ledger-kills (World-ledger world))) (show (Hub-health (World-hub world)))
                     (string-join (map (lambda (w) (string-append (show (Worker-id w)) "@" (cell-text (Worker-cell w)) ":" (show (Worker-health w)))) (World-workers world)) ",")
                     (string-join (map building-text (World-buildings world)) ",")
                     (string-join (map (lambda (e) (string-append (show (Enemy-id e)) "@" (cell-text (Enemy-cell e)) ":" (show (Enemy-health e)))) (World-enemies world)) ",")
                     (string-join (map (lambda (n) (show (Nest-health n))) (World-nests world)) ",")
                     (string-join (map (lambda (c) (show (Crystal-reserve c))) (World-crystals world)) ","))
               " "))

(: building-text (-> Building String))
(define (building-text b)
  (string-append (show (Building-id b)) (kind-name (Building-kind b)) (cell-text (Building-cell b)) "L" (show (Building-level b)) "H" (show (Building-health b))
                 (match (Building-work b) ((Some work) (string-append "W" (show (Work-progress work)))) ((None) ""))))

(: cell-text (-> Cell String))
(define (cell-text cell)
  (string-append (show (Cell-x cell)) "." (show (Cell-y cell))))

(let ()
  (define start (Played (new-world 3) (Nil)))
  (define start (give start (Build (Extractor) (Land-starter (World-land (Played-world start))) #f)))
  (define played (play start 20))
  (define world (Played-world played))
  (define journal (reverse (Played-journal played)))
  (write-line (string-append "played to tick " (show (World-tick world)) " with " (show (length journal)) " orders, "
                             (show (length (World-buildings world))) " buildings and " (show (Ledger-kills (World-ledger world))) " kills"))
  (write-line (string-append "replay matches: " (show (string=? (fingerprint (Pair-first (replay 3 journal (World-tick world)))) (fingerprint world)))))
  (define stray (Cons (Entry 0 (Build (Turret) (offset world 1 1) #f)) journal))
  (write-line (string-append "replay skipping a rejected order matches: " (show (string=? (fingerprint (Pair-first (replay 3 stray (World-tick world)))) (fingerprint world)))))
  (write-line (string-append "and drops it from the journal: " (show (= (length (Pair-second (replay 3 stray (World-tick world)))) (length journal)))))
  (define bytes (serialize journal))
  (define decoded (ann (deserialize bytes) (List Entry)))
  (write-line (string-append "decoded journal matches: " (show (string=? (fingerprint (Pair-first (replay 3 decoded (World-tick world)))) (fingerprint world)))))
  (write-line (string-append "journal of " (show (vector-length bytes)) " bytes")))
