(import
 (lofi serialization))
(data Dynamic ()
  (dynamic
   (value Any))
  (deriving derive-deserialize))
(ann 42 I32)
