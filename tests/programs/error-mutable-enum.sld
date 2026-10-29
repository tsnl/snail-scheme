(import
 (snail core base))

;; A case accessor is partial, so an enum's fields stay immutable.
(enum Shape
  (Circle ((radius mut I64)))
  (Empty))
