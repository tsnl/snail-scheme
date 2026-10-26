;; Deterministic pseudo-random numbers: a SplitMix64 generator as a value.
(define-library (lofi random)
  (export
   Random
   make-random
   random-next
   random-below
   random-value
   random-state)
  (import
   (lofi base)
   (lofi wire)
   (except (lofi primitive) string-append))
  (begin

    ;; `value` is the latest output; advancing returns a new generator.
    (struct Random
      ((state I64)
       (value I64))
      (deriving Serialize Deserialize))

    (: make-random (-> I64 Random))
    (define (make-random seed)
      (random-next (Random seed 0)))

    (: random-next (-> Random Random))
    (define (random-next random)
      (let* ((state (+ (Random-state random) -7046029254386353131))
             (z (i64-xor state (i64-shift-right/logical state 30)))
             (z (* z -4658895280553007687))
             (z (i64-xor z (i64-shift-right/logical z 27)))
             (z (* z -7723592293110705685)))
        (Random state (i64-xor z (i64-shift-right/logical z 31)))))

    (: random-value (-> Random I64))
    (define (random-value random)
      (Random-value random))

    (: random-state (-> Random I64))
    (define (random-state random)
      (Random-state random))

    ;; The latest output reduced to [0, bound).
    (: random-below (-> Random I64 I64))
    (define (random-below random bound)
      (modulo (i64-shift-right/logical (Random-value random) 1) bound))

    ))
