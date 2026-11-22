(import
 (snail core base)
 (snail core io)
 (snail shell wire))

(record Old
  ((count I64))
  (deriving Serialize Deserialize))

(record New
  ((count I64)
   (label String))
  (deriving Serialize Deserialize))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (write-line out "decoding")
  (match (ann (deserialize (serialize (new Old (count 3)))) New)
    ((New count label) (write-line out label)))
  (unit))
