(import
 (snail core base)
 (snail core io)
 (snail shell wire))

(struct Old
  ((count I64))
  (deriving Serialize Deserialize))

(struct New
  ((count I64)
   (label String))
  (deriving Serialize Deserialize))

(write-line "decoding")
(match (ann (deserialize (serialize (Old 3))) New)
  ((New count label) (write-line label)))
