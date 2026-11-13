(import
 (snail core base)
 (snail core io))

(typeclass (First A)
  (type Output)
  (: first (Fn A → Output)))

(typeclass (Second A)
  (type Output)
  (: second (Fn A → Output)))

(instance (First A)
  (⊨ (Second A))
  (type Output (Second.Output A))
  (define first (lambda (value) (second value))))

(instance (Second A)
  (⊨ (First A))
  (type Output (First.Output A))
  (define second (lambda (value) (first value))))

(define main
  (lambda ()
    (first (ann 1 I64))
    (unit)))
