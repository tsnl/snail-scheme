(import
 (snail core base))

(instance (Num (! dyn-cast) Any)
  (dispatch I64 I64))
