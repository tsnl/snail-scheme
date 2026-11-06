(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(: consume (-> Token Unit))
(define (consume token)
  (match token ((Token _) (unit))))

(let ((token (Token 1)) (other (Token 2)))
  (with-borrow (borrowed token)
               (consume other)
               (::number borrowed))
  (consume other)
  (drop token))
