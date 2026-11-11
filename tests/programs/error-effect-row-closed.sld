(import
 (snail core base)
 (snail core io))

(: call (All (A e) (impl (Fn (dyn (Fn -> A ! e)) -> A ! e))))
(define (call action) (action))

(: escape (impl (Fn -> Unit)))
(define (escape) (call (lambda () (write-line "escaped"))))
