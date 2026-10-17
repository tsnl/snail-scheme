(define-library (tests type-name)
  (import
   (rename (lofi core) (type-name portable-name))
   (only (lofi base) string=?)
   (rename (only (macro deriving) derive-type-key) (derive-type-key derive-key)))
  (begin
    (data Box (T)
      (box
       (schema T box-value))
      (deriving derive-key))
    (if (string=? schema "(tests type-name):Box")
        ((lambda (Box) (if (string=? (portable-name Box) schema) 42 0)) 0)
        0)))
