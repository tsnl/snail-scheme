(import
 (snail core base))

(typeclass (ReadValue T)
  (: read-value (impl (Fn (List T) → String))))

(instance (ReadValue Any)
  (dispatch String))
