;; The water jug puzzle as a bounded search: with jugs of 3 and 5 litres,
;; the shortest way to measure 4 litres.
(import
 (snail core base)
 (snail core io)
 (snail shell wire)
 (snail shell explore))

(record Jugs
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
      ((FillSmall) (new Jugs (small 3) (large large)))
      ((FillLarge) (new Jugs (small small) (large 5)))
      ((EmptySmall) (new Jugs (small 0) (large large)))
      ((EmptyLarge) (new Jugs (small small) (large 0)))
      ((SmallToLarge)
       (let ((amount (min small (- 5 large))))
         (new Jugs (small (- small amount)) (large (+ large amount)))))
      ((LargeToSmall)
       (let ((amount (min large (- 3 small))))
         (new Jugs (small (+ small amount)) (large (- large amount))))))))

(define (describe (move Pour)) (→ String)
  (match move
    ((FillSmall) "fill the small jug")
    ((FillLarge) "fill the large jug")
    ((EmptySmall) "empty the small jug")
    ((EmptyLarge) "empty the large jug")
    ((SmallToLarge) "pour small into large")
    ((LargeToSmall) "pour large into small")))

(define (main) (→ Unit) (! output-port)

  (match (explore (new Jugs (small 0) (large 0))
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
