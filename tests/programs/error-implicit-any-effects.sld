(import
 (snail core base)
 (snail core io))

(define (boxed (out OutputPort)) (→ Any) (lambda () (write-line out "hidden")))
