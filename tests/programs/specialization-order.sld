(import
 (snail core base)
 (snail core io)
 (sample specialization))

;; Definitions initialize before statements, in both whole-program and
;; library builds, even when a statement precedes the definition in source.
(write-line (show (advance)))

(define third (→ I64) (+ second (advance)))

(write-line (show first))
(write-line (show second))
(write-line (show third))
(write-line (show (round-trip 17 100)))
(write-line (round-trip "again" 99))
(write-line (show (round-trip 23 2)))

;; The library module imports this same function for both its host wrapper
;; and its ordinary call; neither path may enqueue an imported body.
(expose fixed "fixed")
(write-line (show (fixed 41)))

;; Reading the inner list catches an initializer that captured its
;; dependency's default null value before that dependency was initialized.
(match (ann nested-values (List (List I64)))
  ((Cons values _) (write-line (show (length values))))
  ((Nil) (panic "missing integer list")))
(match (ann nested-values (List (List String)))
  ((Cons values _) (write-line (show (length values))))
  ((Nil) (panic "missing string list")))
