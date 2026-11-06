(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(: escape (-> (Borrow Token) (Borrow Token)))
(define (escape borrowed)
  borrowed)
