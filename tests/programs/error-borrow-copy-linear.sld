(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(define (steal (borrowed (Borrow Token))) (→ Token)
  (borrow-copy borrowed))
