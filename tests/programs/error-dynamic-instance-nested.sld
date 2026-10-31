(import
 (snail core base))

(typeclass (ReadValue T)
  (: read-value (-> (List T) String)))

(instance (ReadValue Any)
  (dispatch String))
