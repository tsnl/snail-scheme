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
  (Fill-small)
  (Fill-large)
  (Empty-small)
  (Empty-large)
  (Small-to-large)
  (Large-to-small))

(define (pour (jugs Jugs) (move Pour)) (→ Jugs)
  (let ((small (● jugs small)) (large (● jugs large)))
    (match move
      ((Fill-small) (new Jugs (small 3) (large large)))
      ((Fill-large) (new Jugs (small small) (large 5)))
      ((Empty-small) (new Jugs (small 0) (large large)))
      ((Empty-large) (new Jugs (small small) (large 0)))
      ((Small-to-large)
       (let ((amount (min small (- 5 large))))
         (new Jugs (small (- small amount)) (large (+ large amount)))))
      ((Large-to-small)
       (let ((amount (min large (- 3 small))))
         (new Jugs (small (+ small amount)) (large (- large amount))))))))

(define (describe (move Pour)) (→ String)
  (match move
    ((Fill-small) "fill the small jug")
    ((Fill-large) "fill the large jug")
    ((Empty-small) "empty the small jug")
    ((Empty-large) "empty the large jug")
    ((Small-to-large) "pour small into large")
    ((Large-to-small) "pour large into small")))

(define (main) (→ Unit) (! Output-port)

  (match (explore (new Jugs (small 0) (large 0))
                  (lambda (jugs)
                    (list (Fill-small)
                          (Fill-large)
                          (Empty-small)
                          (Empty-large)
                          (Small-to-large)
                          (Large-to-small)))
                  pour
                  (lambda (jugs)
                    (if (= (● jugs large) 4) (Some "the large jug holds 4 litres") (None)))
                  10)
    ((Some violation)
     (for-each (lambda (move) (write-line (describe move))) (● violation moves))
     (write-line (● violation reason)))
    ((None) (write-line "no state within 10 moves")))
  (unit))
