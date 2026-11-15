(import
 (snail core base))

;; Unrelated quantified tails cannot be treated as interchangeable.
(define (escape (action (Fn → A ! e))) (→ A) (! f) (∀ (A e f)) (action))
