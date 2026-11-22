;; A script that embeds its own build, which a build refuses.
(import
 (snail core base)
 (embedded own))

(define (main) (→ Unit)
  (unit))
