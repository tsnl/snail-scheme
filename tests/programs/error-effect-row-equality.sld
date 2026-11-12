(import
 (snail core base)
 (snail core io))

;; Call-site inclusion must not silently widen function values.
(define (widen (action (dyn (Fn → A ! e)))) (→ (dyn (Fn → A ! output-port e))) (∀ A e) action)
