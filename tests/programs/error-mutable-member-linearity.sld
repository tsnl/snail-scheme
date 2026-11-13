(import
 (snail core base))

(struct Token
  ((id I64)) (deriving Move))

(struct Owner
  ((token Token)))

(define main
  (lambda ()
    (let ((owner (Owner (Token 1))))
      (drop owner)
      (drop owner))
    (unit)))
