(import
 (snail core base))

(typeclass (ReadValue T)
  (: read-value (-> T String)))

(instance (ReadValue Any)
  (dispatch String))
