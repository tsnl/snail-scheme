(import
 (snail core base))

(typeclass (Identity T)
  (declare (identity (value T)) (→ T) value))
