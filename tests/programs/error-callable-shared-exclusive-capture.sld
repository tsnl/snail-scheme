(import
 (snail core base))

(struct Token
  ((value I64)))

(instance (Drop (!) Token)
  (define (drop (token Token)) (→ Unit)
    (match token ((Token _) (unit)))))

(define main
  (lambda ()
    (let* ((token (Token 1))
           (inner (ann (lambda () (● token value)) (Fn → I64)))
           (outer (ann (lambda () (inner)) (Fn → I64))))
      (drop outer))
    (unit)))
