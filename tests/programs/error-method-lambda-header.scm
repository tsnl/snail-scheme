(import
 (snail core base))
(typeclass (Identity T) (declare (identity (value T)) (→ T)))
(instance (Identity I64) (define identity (→ (Fn String → String)) (lambda (value) value)))
