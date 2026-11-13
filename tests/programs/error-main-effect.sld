(import
 (snail core base))
(effect External ((observe (Fn → Unit))))
(define (main) (→ Unit) (! External)
  (observe))
