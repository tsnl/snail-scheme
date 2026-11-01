(import
 (snail core base))

(typeclass (ReadValue e T)
  (: read-value (-> T String ! e)))

(instance (ReadValue (! dyn-cast) Any)
  (dispatch String))
