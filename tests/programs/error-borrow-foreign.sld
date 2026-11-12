(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(extern retain "test" "retain" (Fn (Borrow Token) → Unit))

(define main
  (lambda ()
    (let ((token (Token 1)))
      (let ((send retain))
        (with-borrow (borrowed token) (send borrowed)))
      (drop token))
    (unit)))
