(import
 (snail core base)
 (snail core io)
 (sample specialization))

(define (third) (→ I64) (+ (second) 4))

;; The library module imports this same function for both its host wrapper
;; and its ordinary call; neither path may enqueue an imported body.
(expose fixed "fixed")

(define (main (out OutputPort)) (→ Unit)

  ;; Source and emission order do not affect dependency forcing.
  (write-line out (show (first)))
  (write-line out (show (second)))
  (write-line out (show (third)))
  (write-line out (show (round-trip 17 100)))
  (write-line out (round-trip "again" 99))
  (write-line out (show (round-trip 23 2)))
  (write-line out (show (fixed 41)))
  ;; Generic constructors can use imported stateless templates.
  (match (ann (nested-values) (List (List I64)))
    ((Cons values _) (write-line out (show (length values))))
    ((Nil) (panic "missing integer list")))
  (match (ann (nested-values) (List (List String)))
    ((Cons values _) (write-line out (show (length values))))
    ((Nil) (panic "missing string list")))
  (unit))
