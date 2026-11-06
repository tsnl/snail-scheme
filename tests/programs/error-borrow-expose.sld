(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(: inspect (-> (Borrow Token) I64))
(define (inspect borrowed)
  (Token-number borrowed))

(expose inspect "inspect")
