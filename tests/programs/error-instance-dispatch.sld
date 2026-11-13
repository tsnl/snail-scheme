(import
 (snail core base))

(typeclass (Describe A) (: describe (Fn A → String)))
(instance (Describe Any) (dispatch I64))
