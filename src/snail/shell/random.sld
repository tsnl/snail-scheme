;; Deterministic pseudo-random numbers: a SplitMix64 generator as a value.
(define-library (snail shell random)
  (export
   Random
   make-random
   random-next
   random-below
   random-value
   random-state)
  (import
   (snail core base)
   (snail shell wire)
   (except (snail core primitive) string-append))
  (begin

    ;; `value` is the latest output; advancing returns a new generator.
    (record Random
      ((state I64)
       (value I64))
      (deriving Serialize Deserialize))

    (define (make-random (seed I64)) (→ Random)
      (random-next (new Random (state seed) (value 0))))

    (define (random-next (random Random)) (→ Random)
      (let* ((state (+ (● random state) -7046029254386353131))
             (z (i64-xor state (i64-shift-right/logical state 30)))
             (z (* z -4658895280553007687))
             (z (i64-xor z (i64-shift-right/logical z 27)))
             (z (* z -7723592293110705685)))
        (new Random (state state) (value (i64-xor z (i64-shift-right/logical z 31))))))

    (define (random-value (random Random)) (→ I64)
      (● random value))

    (define (random-state (random Random)) (→ I64)
      (● random state))

    ;; The latest output reduced to [0, bound).

    (define (random-below (random Random) (bound I64)) (→ I64)
      (modulo (i64-shift-right/logical (● random value) 1) bound))

    ))
