(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(: both (-> (Borrow Token) Token Unit))
(define (both borrowed owned)
  (drop owned))

(let ((token (Token 1)))
  (with-borrow (borrowed token)
               (both borrowed token)))
