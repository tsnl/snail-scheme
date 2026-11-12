(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(define (conceal (value T)) (→ (Fn → Unit)) (∀ T) (⊨ (Copy T))
  (lambda () (drop value)))

(define main
  (lambda ()
    (let ((token (Token 1)))
      (with-borrow (borrowed token) (conceal borrowed))
      (drop token))
    (unit)))
