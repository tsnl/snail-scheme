(import
 (snail core base))

(typeclass (Describe A) (declare (describe (value A)) (→ String)))
(instance (Describe Any) (dispatch I64))
