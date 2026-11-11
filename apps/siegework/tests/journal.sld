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
  (match (command (::world played) action)
    ((Ok (Pair world entry)) (Played world (Cons entry (::journal played))))
    ((Err _) played)))

(define (run (played Played) (ticks I64)) (→ Played)
  (if (= ticks 0)
      played
      (run (Played-world-set played (advance (::world played))) (- ticks 1))))

(define (offset (world World) (dx I64) (dy I64)) (→ Cell)
  (let ((hub (::cell (::hub world))))
    (Cell (+ (::x hub) dx) (+ (::y hub) dy))))

(define (reinforce (played Played)) (→ Played)
  (let ((world (::world played)))
    (give (fold-left (lambda (played d)
                       (give played
                             (Build (Turret) (offset world (::first d) (::second d)) #f)))
                     played
                     (list (Pair -2 0) (Pair 0 2) (Pair 2 0) (Pair 0 -2) (Pair -2 2) (Pair 2 -2)))
          (Upgrade (offset world 0 0)))))

(define (play (played Played) (rounds I64)) (→ Played)
  (if (= rounds 0) played (play (run (reinforce played) 100) (- rounds 1))))

;; Everything the rules decide, as text.
(define (fingerprint (world World)) (→ String)
  (string-join (list (show (::tick world))
                     (show (::energy world))
                     (show (::produced (::ledger world)))
                     (show (::spent (::ledger world)))
                     (show (::kills (::ledger world)))
                     (show (::health (::hub world)))
                     (show (::slots (::hub world)))
                     (string-join (map building-text (::buildings world)) ",")
                     (string-join (map (lambda (e)
                                         (string-append (show (::id e))
                                                        "@"
                                                        (cell-text (::cell e))
                                                        ":"
                                                        (show (::health e))))
                                       (::enemies world))
                                  ",")
                     (string-join (map (lambda (n) (show (::health n))) (::nests world)) ",")
                     (string-join
                      (map (lambda (c) (show (::reserve c))) (::crystals world))
                      ","))
               " "))

(define (building-text (b Building)) (→ String)
  (string-append (show (::id b))
                 (kind-name (::kind b))
                 (cell-text (::cell b))
                 "L"
                 (show (::level b))
                 "H"
                 (show (::health b))
                 (match (::work b)
                   ((Some work) (string-append "W" (show (::progress work))))
                   ((None) ""))))

(define (cell-text (cell Cell)) (→ String)
  (string-append (show (::x cell)) "." (show (::y cell))))

(let ()
  (define start (Played (new-world 3) (Nil)))
  (define start
    (give start (Build (Extractor) (::starter (::land (::world start))) #f)))
  (define played (play start 20))
  (define world (::world played))
  (define journal (reverse (::journal played)))
  (write-line (string-append "played to tick "
                             (show (::tick world))
                             " with "
                             (show (length journal))
                             " orders, "
                             (show (length (::buildings world)))
                             " buildings and "
                             (show (::kills (::ledger world)))
                             " kills"))
  (write-line (string-append "replay matches: "
                             (show (string=?
                                    (fingerprint (::first (replay 3 journal (::tick world))))
                                    (fingerprint world)))))
  (define stray (Cons (Entry 0 (Build (Turret) (offset world 1 1) #f)) journal))
  (write-line (string-append "replay skipping a rejected order matches: "
                             (show (string=?
                                    (fingerprint (::first (replay 3 stray (::tick world))))
                                    (fingerprint world)))))
  (write-line (string-append "and drops it from the journal: "
                             (show (= (length (::second (replay 3 stray (::tick world))))
                                      (length journal)))))
  (define bytes (serialize journal))
  (define decoded (ann (deserialize bytes) (List Entry)))
  (write-line (string-append "decoded journal matches: "
                             (show (string=?
                                    (fingerprint (::first (replay 3 decoded (::tick world))))
                                    (fingerprint world)))))
  (write-line (string-append "journal of " (show (vector-length bytes)) " bytes")))
