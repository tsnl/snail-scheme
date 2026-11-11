(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(define (escape (borrowed (Borrow Token))) (→ (dyn (FnOnce → I64)))
  (once (lambda () (::number borrowed))))
