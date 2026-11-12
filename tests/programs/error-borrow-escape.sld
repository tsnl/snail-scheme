(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(define main
  (lambda ()
    (let ((token (Token 1)))
      (let ((escaped (with-borrow (borrowed token) borrowed)))
        (drop token)
        (unit)))
    (unit)))
