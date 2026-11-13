(import
 (snail core base))

(struct Work
  ((run (FnOnce → Unit))))

;; Owning a linear field makes the whole struct linear.
(define (duplicate (work Work)) (→ (Pair Work Work))
  (Pair work work))
