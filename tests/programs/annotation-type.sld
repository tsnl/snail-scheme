(import
 (snail core base)
 (snail core io))
(struct (annotations T)
  ((value T)))
(struct Wrapped
  ((item (annotations I64) (annotations (doc "An ordinary applied type.")))))
(define item (→ (annotations I64)) (annotations (doc "A value of that type.")) (annotations 9))
(write-line (show (::value (::item (Wrapped item)))))
