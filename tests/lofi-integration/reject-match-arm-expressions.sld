(import
 (lofi core))

(data Box ()
  (box
   (value I32 box-value)))
(match (box 0)
  ((box value) value 42))
