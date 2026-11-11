(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(define (inspect (borrowed (Borrow Token))) (→ I64)
  (● borrowed number))

(let ((token (Token 1)))
  (inspect token)
  (drop token))
