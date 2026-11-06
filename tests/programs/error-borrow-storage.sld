(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(let ((token (Token 1)))
  (with-borrow (borrowed token)
               (let ((stored (ref borrowed))) (unit)))
  (drop token))
