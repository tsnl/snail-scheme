(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(define (consume (token Token)) (→ Unit)
  (match token ((Token _) (unit))))

(let ((token (Token 1)) (other (Token 2)))
  (with-borrow (borrowed token)
               (consume other)
               (::number borrowed))
  (consume other)
  (drop token))
