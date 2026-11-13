(import
 (snail core base))

(record Token
  ((id I64)) )
(instance (Drop (!) Token)
  (define (drop (value Token)) (→ Unit)
    (match value ((Token _) (unit)))))

(record Owner
  ((token Token)))

(define main
  (lambda ()
    (let ((owner (new Owner (token (new Token (id 1))))))
      (drop owner)
      (drop owner))
    (unit)))
