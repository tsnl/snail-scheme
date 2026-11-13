(import
 (snail core base))

;; A token is linear by its declaration, so it must be used.
(struct Token
  ((id I64))
  (deriving Move))

(define main
  (lambda ()
    (let ((token (Token 1)))
      (unit))
    (unit)))
