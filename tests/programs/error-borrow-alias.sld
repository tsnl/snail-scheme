(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(define (both (borrowed (Borrow Token)) (owned Token)) (→ Unit)
  (drop owned))

(define main
  (lambda ()
    (let ((token (Token 1)))
      (with-borrow (borrowed token)
                   (both borrowed token)))
    (unit)))
