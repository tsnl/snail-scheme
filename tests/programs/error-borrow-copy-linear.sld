(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(: steal (-> (Borrow Token) Token))
(define (steal borrowed)
  (borrow-copy borrowed))
