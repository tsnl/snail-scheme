(import
 (snail core base)
 (snail core io))

;; An unknown rigid row cannot fit a closed set of permissions.
(: escape (All (A e) (impl (Fn (dyn (Fn -> A ! e)) -> A ! console))))
(define (escape action) (action))
