(import
 (snail core base))

;; Dropping a value of a type variable needs the row of its release.
(: discard-it (All (A) (impl (Fn A -> Unit))))
(define (discard-it value)
  (drop value))
