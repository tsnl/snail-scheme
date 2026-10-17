(import
 (lofi core)
 (only (macro deriving) derive-instance read-derived))

(data Box ()
  (box
   (value I32 box-value))
  (deriving derive-instance))
(read-derived (box 41))
