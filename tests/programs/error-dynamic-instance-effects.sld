(import
 (snail core base)
 (snail core io))

(typeclass (ReadValue e T)
  (: read-value (Fn T → String ! e)))

(instance (ReadValue (! output-port) String)
  (define read-value
    (lambda (value) (write-line value)
            value)))

(instance (ReadValue (! dyn-cast) Any)
  (dispatch String))
