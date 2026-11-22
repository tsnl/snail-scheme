(import
 (snail core base)
 (snail core io))

(define (call (action (Fn → A ! e))) (→ A) (! e) (∀ (A e)) (action))

(define (escape (out OutputPort)) (→ Unit) (call (lambda () (write-line out "escaped"))))
