(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(define (conceal (value T)) (→ (dyn (Fn → Unit))) (∀ T) (⊨ (Copy T))
  (lambda () (drop value)))

(let ((token (Token 1)))
  (with-borrow (borrowed token) (conceal borrowed))
  (drop token))
