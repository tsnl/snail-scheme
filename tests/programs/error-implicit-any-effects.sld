(import
 (snail core base)
 (snail core io))

(define boxed (→ Any) (lambda () (write-line "hidden")))
