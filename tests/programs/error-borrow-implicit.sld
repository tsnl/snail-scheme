(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(: inspect (-> (Borrow Token) I64))
(define (inspect borrowed)
  (::number borrowed))

(let ((token (Token 1)))
  (inspect token)
  (drop token))
