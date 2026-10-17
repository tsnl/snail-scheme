(import
 (lofi serialization))
(data Box (T)
  (box
   (value T))
  (deriving derive-serialize))
(ann 42 I32)
