(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(define (consume (token Token)) (→ Unit)
  (match token ((Token _) (unit))))

(define main
  (lambda ()
    (let ((token (Token 1)) (other (Token 2)))
      (with-borrow (borrowed token)
                   (consume other)
                   (● borrowed number))
      (consume other)
      (drop token))
    (unit)))
