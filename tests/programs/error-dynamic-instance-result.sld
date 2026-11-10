(import
 (snail core base))

(typeclass (ReadValue T)
  (: read-value (impl (Fn String -> T))))

(instance (ReadValue Any)
  (dispatch I64))
