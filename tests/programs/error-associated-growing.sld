(import
 (snail core base))

(typeclass (Grow A)
  (type Output)
  (declare (grow (value A)) (→ Output)))

(instance (Grow A)
  (⊨ (Grow (List A)))
  (type Output (Grow.Output (List A)))
  (define (grow (value A)) (→ (Grow.Output (List A)))
    (grow (list value))))

(define main
  (lambda ()
    (grow (ann 1 I64))
    (unit)))
