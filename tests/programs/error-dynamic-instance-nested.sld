(import
 (snail core base))

(typeclass (ReadValue T)
  (: read-value (Fn (List T) → String)))

(instance (ReadValue Any)
  (dispatch String))
