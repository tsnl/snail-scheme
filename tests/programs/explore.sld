;; The water jug puzzle as a bounded search: with jugs of 3 and 5 litres,
;; the shortest way to measure 4 litres.
(import
 (snail-core base)
 (snail-core io)
 (snail-core wire)
 (snail-core explore))

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

(: pour (-> Jugs Pour Jugs))
(define (pour jugs move)
  (let ((small (Jugs-small jugs)) (large (Jugs-large jugs)))
    (match move
      ((FillSmall) (Jugs 3 large))
      ((FillLarge) (Jugs small 5))
      ((EmptySmall) (Jugs 0 large))
      ((EmptyLarge) (Jugs small 0))
      ((SmallToLarge)
       (let ((amount (min small (- 5 large))))
         (Jugs (- small amount) (+ large amount))))
      ((LargeToSmall)
       (let ((amount (min large (- 3 small))))
         (Jugs (+ small amount) (- large amount)))))))

(: describe (-> Pour String))
(define (describe move)
  (match move
    ((FillSmall) "fill the small jug")
    ((FillLarge) "fill the large jug")
    ((EmptySmall) "empty the small jug")
    ((EmptyLarge) "empty the large jug")
    ((SmallToLarge) "pour small into large")
    ((LargeToSmall) "pour large into small")))

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
                  (if (= (Jugs-large jugs) 4)
                      (Some "the large jug holds 4 litres")
                      (None)))
                10)
  ((Some violation)
   (for-each (lambda (move) (write-line (describe move)))
             (Violation-moves violation))
   (write-line (Violation-reason violation)))
  ((None) (write-line "no state within 10 moves")))
