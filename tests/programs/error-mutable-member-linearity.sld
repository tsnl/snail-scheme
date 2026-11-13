(import
 (snail core base))

(struct Token
  ((id I64)) )
(instance (Drop (!) Token)
  (define (drop (value Token)) (→ Unit)
    (match value ((Token _) (unit)))))

(struct Owner
  ((token Token)))

(define main
  (lambda ()
    (let ((owner (Owner (Token 1))))
      (drop owner)
      (drop owner))
    (unit)))
