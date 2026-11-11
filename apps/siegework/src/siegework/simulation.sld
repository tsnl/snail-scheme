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
    (: advance (impl (Fn World -> World)))
    (define (advance world)
      (if (and (::started world) (playing? world))
          (judge (settle
                  (strike (settle (fire (march (excavate (spawn (work (produce (World-tick-set world
                                                                                               (+
                                                                                                (::tick
                                                                                                 world)
                                                                                                1))))))))))))
          world))

    ;; ---- Journal ----

    ;; An order the world accepted, with the tick it was given at. A seed
    ;; and the journal of a colony's orders rebuild the colony exactly.
    (struct Entry
      ((tick I64)
       (action Action))
      (deriving Serialize Deserialize))

    ;; Gives an order, returning the world and its journal entry, or why the
    ;; order was rejected.
    (: command (impl (Fn World Action -> (Result (Pair World Entry) Rejection))))
    (define (command world action)
      (match (act world action)
        ((Ok next) (Ok (Pair next (Entry (::tick world) action))))
        ((Err rejection) (Err rejection))))

    ;; Rebuilds a colony from its seed, its journal, oldest entry first, and
    ;; the tick it had reached; returns the world and the journal of the
    ;; orders it accepted. Each order is given when the world reaches its
    ;; tick, through `command` as in play. Under rules that have changed
    ;; since the journal was written, an order the world now rejects, or
    ;; whose tick the world no longer reaches, is dropped.
    (: replay (impl (Fn I64 (List Entry) I64 -> (Pair World (List Entry)))))
    (define (replay seed entries tick)
      (match (fold-left replay-entry (Pair (new-world seed) (Nil)) entries)
        ((Pair world kept) (Pair (advance-until world tick) (reverse kept)))))

    (: replay-entry (impl (Fn (Pair World (List Entry)) Entry -> (Pair World (List Entry)))))
    (define (replay-entry played entry)
      (let ((world (advance-until (::first played) (::tick entry))))
        (if (= (::tick world) (::tick entry))
            (match (command world (::action entry))
              ((Ok (Pair next kept)) (Pair next (Cons kept (::second played))))
              ((Err _) (Pair world (::second played))))
            (Pair world (::second played)))))

    ;; Advances to `tick`, or until the world stops: before the first order
    ;; and once the game is decided, a tick changes nothing.
    (: advance-until (impl (Fn World I64 -> World)))
    (define (advance-until world tick)
      (if (< (::tick world) tick)
          (let ((next (advance world)))
            (if (= (::tick next) (::tick world)) next (advance-until next tick)))
          world))

    ))
