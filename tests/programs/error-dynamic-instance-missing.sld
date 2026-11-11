(import
 (snail core base))

(typeclass (ReadValue e T)
  (: read-value (impl (Fn T → String ! e))))

(instance (ReadValue (! dyn-cast) Any)
  (dispatch String))
