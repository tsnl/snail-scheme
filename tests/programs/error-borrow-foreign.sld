(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(extern retain "test" "retain" (impl (Fn (Borrow Token) -> Unit)))

(let ((token (Token 1)))
  (let ((send retain))
    (with-borrow (borrowed token) (send borrowed)))
  (drop token))
