;; A colony rebuilt from its seed and journal is the colony that was
;; played. A defended game on seed 3 is played through `command`, which
;; journals each accepted order; replaying the journal must reproduce the
;; world exactly, even with a rejected order slipped in, and the journal
;; must survive its wire encoding.
(import
 (snail core base)
 (snail core io)
 (snail shell wire)
 (siegework grid)
 (only (siegework terrain))
 (siegework world)
 (siegework colony)
 (siegework simulation))

;; A game in progress: the world and its journal, newest entry first.
(struct Played
  ((world World)
   (journal (List Entry))))

(define (give (played Played) (action Action)) (→ Played)
  (match (command (● played world) action)
    ((Ok (Pair world entry)) (Played world (Cons entry (● played journal))))
    ((Err _) played)))

(define (run (played Played) (ticks I64)) (→ Played)
  (if (= ticks 0)
      played
      (run (Played-world-set played (advance (● played world))) (- ticks 1))))

(define (offset (world World) (dx I64) (dy I64)) (→ Cell)
  (let ((hub (● (● world hub) cell)))
    (Cell (+ (● hub x) dx) (+ (● hub y) dy))))

(define (reinforce (played Played)) (→ Played)
  (let ((world (● played world)))
    (give (fold-left (lambda (played d)
                       (give played
                             (Build (Turret) (offset world (● d first) (● d second)) #f)))
                     played
                     (list (Pair -2 0) (Pair 0 2) (Pair 2 0) (Pair 0 -2) (Pair -2 2) (Pair 2 -2)))
          (Upgrade (offset world 0 0)))))

(define (play (played Played) (rounds I64)) (→ Played)
  (if (= rounds 0) played (play (run (reinforce played) 100) (- rounds 1))))

;; Everything the rules decide, as text.
(define (fingerprint (world World)) (→ String)
  (string-join (list (show (● world tick))
                     (show (● world energy))
                     (show (● (● world ledger) produced))
                     (show (● (● world ledger) spent))
                     (show (● (● world ledger) kills))
                     (show (● (● world hub) health))
                     (show (● (● world hub) slots))
                     (string-join (map building-text (● world buildings)) ",")
                     (string-join (map (lambda (e)
                                         (string-append (show (● e id))
                                                        "@"
                                                        (cell-text (● e cell))
                                                        ":"
                                                        (show (● e health))))
                                       (● world enemies))
                                  ",")
                     (string-join (map (lambda (n) (show (● n health))) (● world nests)) ",")
                     (string-join
                      (map (lambda (c) (show (● c reserve))) (● world crystals))
                      ","))
               " "))

(define (building-text (b Building)) (→ String)
  (string-append (show (● b id))
                 (kind-name (● b kind))
                 (cell-text (● b cell))
                 "L"
                 (show (● b level))
                 "H"
                 (show (● b health))
                 (match (● b work)
                   ((Some work) (string-append "W" (show (● work progress))))
                   ((None) ""))))

(define (cell-text (cell Cell)) (→ String)
  (string-append (show (● cell x)) "." (show (● cell y))))

(define (main) (→ Unit) (! output-port)

  (let ()
    (define start (Played (new-world 3) (Nil)))
    (define start
      (give start (Build (Extractor) (● (● (● start world) land) starter) #f)))
    (define played (play start 20))
    (define world (● played world))
    (define journal (reverse (● played journal)))
    (write-line (string-append "played to tick "
                               (show (● world tick))
                               " with "
                               (show (length journal))
                               " orders, "
                               (show (length (● world buildings)))
                               " buildings and "
                               (show (● (● world ledger) kills))
                               " kills"))
    (write-line (string-append "replay matches: "
                               (show (string=?
                                      (fingerprint (● (replay 3 journal (● world tick)) first))
                                      (fingerprint world)))))
    (define stray (Cons (Entry 0 (Build (Turret) (offset world 1 1) #f)) journal))
    (write-line (string-append "replay skipping a rejected order matches: "
                               (show (string=?
                                      (fingerprint (● (replay 3 stray (● world tick)) first))
                                      (fingerprint world)))))
    (write-line (string-append "and drops it from the journal: "
                               (show (= (length (● (replay 3 stray (● world tick)) second))
                                        (length journal)))))
    (define bytes (serialize journal))
    (define decoded (ann (deserialize bytes) (List Entry)))
    (write-line (string-append "decoded journal matches: "
                               (show (string=?
                                      (fingerprint (● (replay 3 decoded (● world tick)) first))
                                      (fingerprint world)))))
    (write-line (string-append "journal of " (show (vector-length bytes)) " bytes")))
  (unit))
