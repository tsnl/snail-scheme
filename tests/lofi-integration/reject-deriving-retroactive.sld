(import
 (lofi core))

(def derive-binding
     (syntax-rules (data)
       ((_ (data Name ()
             (constructor
              (name Type accessor))))
        (def name (lambda (value) value)))))
(data Flag ()
  (flag
   (data I32 flag-value))
  (deriving derive-binding))
42
