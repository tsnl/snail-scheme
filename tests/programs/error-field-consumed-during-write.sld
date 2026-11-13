(import
 (snail core base))

(struct Token
  ((id I64)) (deriving Move))

(struct Owner
  ((token Token)
   (count I64)))

(define main
  (lambda ()
    (let ((owner (Owner (Token 1) 0)))
      (set! (● owner count) (begin (drop owner) 2)))
    (unit)))
