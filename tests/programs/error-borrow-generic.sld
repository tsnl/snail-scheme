(import
 (snail core base))

(struct Token
  ((number I64))
  (deriving Move))

(: conceal (All (T) (requires (Copy T)) (-> T (-> Unit))))
(define (conceal value)
  (lambda () (drop value)))

(let ((token (Token 1)))
  (with-borrow (borrowed token) (conceal borrowed))
  (drop token))
