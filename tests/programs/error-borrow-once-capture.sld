(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(: escape (impl (Fn (Borrow Token) -> (dyn (FnOnce -> I64)))))
(define (escape borrowed)
  (once (lambda () (::number borrowed))))
