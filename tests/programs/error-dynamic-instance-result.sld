(import
 (snail core base))

(typeclass (ReadValue T)
  (: read-value (-> String T)))

(instance (ReadValue Any)
  (dispatch I64))
