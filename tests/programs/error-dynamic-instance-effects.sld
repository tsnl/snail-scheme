(import
 (snail core base)
 (snail core io))

(typeclass (ReadValue e T)
  (: read-value (-> T String ! e)))

(instance (ReadValue (! console) String)
  (define (read-value value)
    (write-line value)
    value))

(instance (ReadValue (!) Any)
  (dispatch String))
