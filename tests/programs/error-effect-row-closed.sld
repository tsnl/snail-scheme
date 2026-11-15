(import
 (snail core base)
 (snail core io))

(define (call (action (Fn → A ! e))) (→ A) (! e) (∀ (A e)) (action))

(define (escape) (→ Unit) (call (lambda () (write-line "escaped"))))
