(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(define (escape (borrowed (Borrow Token))) (→ (FnOnce → I64))
  (once (lambda () (● borrowed number))))
