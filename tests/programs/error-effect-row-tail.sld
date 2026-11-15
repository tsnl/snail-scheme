(import
 (snail core base))

;; Unrelated quantified tails cannot be treated as interchangeable.
(define (escape (action (Fn → A ! E))) (→ A) (! F) (∀ (A E F)) (action))
