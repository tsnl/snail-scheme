(import
 (snail core base)
 (snail core io))
(struct (annotations T)
  ((value T)))
(struct Wrapped
  ((item (annotations I64) (annotations (doc "An ordinary applied type.")))))
(: item (annotations I64) (annotations (doc "A value of that type.")))
(define item (annotations 9))
(write-line (show (annotations-value (Wrapped-item (Wrapped item)))))
