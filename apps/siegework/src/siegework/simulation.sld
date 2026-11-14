;; The two ways the world changes: `act` applies a player's order, and
;; `advance` runs one tick of the rules. Nothing else produces a World, so
;; the colony depends only on its seed and the orders given at each tick,
;; and its journal of those orders is enough to rebuild it.
(define-library (siegework simulation)
  (export
   act
   advance
   Entry
   command
   replay)
  (import
   (snail core base)
   (snail shell wire)
   (siegework world)
   (siegework colony)
   (siegework siege))
  (begin

    ;; ---- Ticks ----

    ;; Nothing happens until the first extractor is ordered, or once the
    ;; game is decided. Production and work come first, so new buildings act
    ;; this tick. Then the nests spawn, burrowers dig, enemies step and
    ;; turrets fire; the dead are removed before the colony is struck, and
    ;; the destroyed before the game is judged.
    (define (advance (world World)) (→ World)
      (if (and (● world started) (playing? world))
          (judge (settle
                  (strike (settle (fire (march (excavate (spawn (work (produce (World-tick-set world
                                                                                               (+
                                                                                                (●
                                                                                                 world
                                                                                                 tick)
                                                                                                1))))))))))))
          world))

    ;; ---- Journal ----

    ;; An order the world accepted, with the tick it was given at. A seed
    ;; and the journal of a colony's orders rebuild the colony exactly.
    (record Entry
      ((tick I64)
       (action Action))
      (deriving Serialize Deserialize))

    ;; Gives an order, returning the world and its journal entry, or why the
    ;; order was rejected.
    (define (command (world World) (action Action)) (→ (Result (Pair World Entry) Rejection))
      (match (act world action)
        ((Ok next)
         (Ok (new Pair (first next) (second (new Entry (tick (● world tick)) (action action))))))
        ((Err rejection) (Err rejection))))

    ;; Rebuilds a colony from its seed, its journal, oldest entry first, and
    ;; the tick it had reached; returns the world and the journal of the
    ;; orders it accepted. Each order is given when the world reaches its
    ;; tick, through `command` as in play. Under rules that have changed
    ;; since the journal was written, an order the world now rejects, or
    ;; whose tick the world no longer reaches, is dropped.
    (define (replay (seed I64) (entries (List Entry)) (tick I64)) (→ (Pair World (List Entry)))
      (match (fold-left replay-entry (new Pair (first (new-world seed)) (second (Nil))) entries)
        ((Pair world kept) (new Pair (first (advance-until world tick)) (second (reverse kept))))))

    (define (replay-entry (played (Pair World (List Entry))) (entry Entry))
      (→ (Pair World (List Entry)))
      (let ((world (advance-until (● played first) (● entry tick))))
        (if (= (● world tick) (● entry tick))
            (match (command world (● entry action))
              ((Ok (Pair next kept)) (new Pair (first next) (second (Cons kept (● played second)))))
              ((Err _) (new Pair (first world) (second (● played second)))))
            (new Pair (first world) (second (● played second))))))

    ;; Advances to `tick`, or until the world stops: before the first order
    ;; and once the game is decided, a tick changes nothing.
    (define (advance-until (world World) (tick I64)) (→ World)
      (if (< (● world tick) tick)
          (let ((next (advance world)))
            (if (= (● next tick) (● world tick)) next (advance-until next tick)))
          world))

    ))
