(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(let ((token (Token 1)))
  (let ((escaped (with-borrow (borrowed token) borrowed)))
    (drop token)
    (unit)))
