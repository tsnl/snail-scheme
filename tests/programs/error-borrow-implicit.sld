(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(define (inspect (borrowed (Borrow Token))) (→ I64)
  (::number borrowed))

(let ((token (Token 1)))
  (inspect token)
  (drop token))
