(import
 (snail core base))
(struct Token
  ((number I64)) (deriving Move))
(instance (::computed Token I64)
  (define ::computed
    (lambda (token) (match token ((Token number) number)))))
(let ((token (Token 1)))
  (with-borrow (borrowed token) (::computed borrowed))
  (drop token))
