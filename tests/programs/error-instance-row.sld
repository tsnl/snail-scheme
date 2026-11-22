(import
 (snail core base))
(typeclass (Describe T)
  (declare (describe (value T)) (→ String)))
(instance (Describe)
  (define describe (lambda (value) "row")))
