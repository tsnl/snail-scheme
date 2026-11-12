(import
 (snail core base))

(typeclass (Twice T)
  (: twice (Fn T → (Pair T T))))

(instance (Twice (Option A))
  (define twice (lambda (value) (Pair value value))))

(define main
  (lambda ()
    (twice (Some 1))
    (unit)))
