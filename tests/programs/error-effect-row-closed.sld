(import
 (snail core base)
 (snail core io))

(define (call (action (Fn → A ! E))) (→ A) (! E) (∀ (A E)) (action))

(define (escape) (→ Unit) (call (lambda () (write-line "escaped"))))
