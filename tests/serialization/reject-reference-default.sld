(import
 (lofi serialization))
(data Item ()
  (item
   (number I32))
  (deriving derive-deserialize))
(data Link ()
  (link
   (value (Ref Item)))
  (deriving derive-deserialize))
(ann 42 I32)
