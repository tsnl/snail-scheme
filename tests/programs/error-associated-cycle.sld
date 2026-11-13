(import
 (snail core base)
 (snail core io))

(typeclass (First A)
  (type Output)
  (declare (first (value A)) (→ Output)))

(typeclass (Second A)
  (type Output)
  (declare (second (value A)) (→ Output)))

(instance (First A)
  (⊨ (Second A))
  (type Output (Second.Output A))
  (define (first (value A)) (→ (Second.Output A))
    (second value)))

(instance (Second A)
  (⊨ (First A))
  (type Output (First.Output A))
  (define (second (value A)) (→ (First.Output A))
    (first value)))

(define main
  (lambda ()
    (first (ann 1 I64))
    (unit)))
