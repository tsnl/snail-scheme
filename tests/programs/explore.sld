;; The water jug puzzle as a bounded search: with jugs of 3 and 5 litres,
;; the shortest way to measure 4 litres.
(import
 (snail core base)
 (snail core io)
 (snail shell wire)
 (snail shell explore))

(struct Jugs
  ((small I64)
   (large I64))
  (deriving Serialize Deserialize))

(enum Pour
  (FillSmall)
  (FillLarge)
  (EmptySmall)
  (EmptyLarge)
  (SmallToLarge)
  (LargeToSmall))

(define (pour (jugs Jugs) (move Pour)) (→ Jugs)
  (let ((small (● jugs small)) (large (● jugs large)))
    (match move
      ((FillSmall) (Jugs 3 large))
      ((FillLarge) (Jugs small 5))
      ((EmptySmall) (Jugs 0 large))
      ((EmptyLarge) (Jugs small 0))
      ((SmallToLarge)
       (let ((amount (min small (- 5 large)))) (Jugs (- small amount) (+ large amount))))
      ((LargeToSmall)
       (let ((amount (min large (- 3 small)))) (Jugs (+ small amount) (- large amount)))))))

(define (describe (move Pour)) (→ String)
  (match move
    ((FillSmall) "fill the small jug")
    ((FillLarge) "fill the large jug")
    ((EmptySmall) "empty the small jug")
    ((EmptyLarge) "empty the large jug")
    ((SmallToLarge) "pour small into large")
    ((LargeToSmall) "pour large into small")))

(define (main) (→ Unit) (! output-port)

  (match (explore (Jugs 0 0)
                  (lambda (jugs)
                    (list (FillSmall)
                          (FillLarge)
                          (EmptySmall)
                          (EmptyLarge)
                          (SmallToLarge)
                          (LargeToSmall)))
                  pour
                  (lambda (jugs)
                    (if (= (● jugs large) 4) (Some "the large jug holds 4 litres") (None)))
                  10)
    ((Some violation)
     (for-each (lambda (move) (write-line (describe move))) (● violation moves))
     (write-line (● violation reason)))
    ((None) (write-line "no state within 10 moves")))
  (unit))
