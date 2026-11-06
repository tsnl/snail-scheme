(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(: escape (-> (Borrow Token) (FnOnce I64)))
(define (escape borrowed)
  (once (lambda () (Token-number borrowed))))
