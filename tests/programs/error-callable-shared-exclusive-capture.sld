(import
 (snail core base))

(record Token
  ((value I64)))

(instance (Drop (!) Token)
  (define (drop (token Token)) (→ Unit)
    (match token ((Token _) (unit)))))

(define main
  (lambda ()
    (let* ((token (new Token (value 1)))
           (inner (ann (lambda () (● token value)) (Fn → I64)))
           (outer (ann (lambda () (inner)) (Fn → I64))))
      (drop outer))
    (unit)))
