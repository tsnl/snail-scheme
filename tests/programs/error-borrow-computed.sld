(import
 (snail core base))

(struct Token
  ((number I64)) (deriving Move))

(define main
  (lambda ()
    (let ((token (Token 1)))
      (with-borrow (borrowed token) (● borrowed computed))
      (drop token))
    (unit)))
