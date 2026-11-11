(import
 (snail core base))
(struct Token
  ((value I64)))
(instance (Drop (!) Token)
  (define drop (lambda (token) (match token ((Token _) (unit))))))
(let* ((token (Token 1))
       (inner (ann (lambda () (::value token)) (impl (FnMut → I64))))
       (outer (ann (lambda () (inner)) (impl (Fn → I64)))))
  (drop outer))
