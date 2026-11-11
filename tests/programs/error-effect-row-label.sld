(import
 (snail core base)
 (snail core io))

;; A shared tail does not authorize a label absent from the context.
(define (escape (action (dyn (Fn → A ! console e)))) (→ A) (! e) (∀ A e) (action))
