(import
 (snail core base)
 (snail core io)
 (sample specialization))

(define third (→ I64) (+ second 4))

;; The library module imports this same function for both its host wrapper
;; and its ordinary call; neither path may enqueue an imported body.
(expose fixed "fixed")

(define main
  (lambda ()
    ;; Source and emission order do not affect dependency forcing.
    (write-line (show first))
    (write-line (show second))
    (write-line (show third))
    (write-line (show (round-trip 17 100)))
    (write-line (round-trip "again" 99))
    (write-line (show (round-trip 23 2)))
    (write-line (show (fixed 41)))
    ;; Each imported generic constant has its dependencies fully evaluated.
    (match (ann nested-values (List (List I64)))
      ((Cons values _) (write-line (show (length values))))
      ((Nil) (panic "missing integer list")))
    (match (ann nested-values (List (List String)))
      ((Cons values _) (write-line (show (length values))))
      ((Nil) (panic "missing string list")))
    (unit)))
