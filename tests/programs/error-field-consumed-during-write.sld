(import
 (snail core base))

(record Token
  ((id I64)) )
(instance (Drop (!) Token)
  (define (drop (value Token)) (→ Unit)
    (match value ((Token _) (unit)))))

(record Owner
  ((token Token)
   (count I64)))

(define main
  (lambda ()
    (let ((owner (new Owner (token (new Token (id 1))) (count 0))))
      (set! (● owner count) (begin (drop owner) 2)))
    (unit)))
