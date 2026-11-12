(import
 (snail core base))

(struct Handle
  ((id I64))
  (deriving Move))

(struct Wrapper
  ((handle Handle))
  (deriving Repr))
