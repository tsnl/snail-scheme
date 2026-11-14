(import
 (snail core base))

;; A token is linear by its declaration, so it must be used.
(record Token
  ((id I64))
  )
(instance (Drop (!) Token)
  (define (drop (value Token)) (→ Unit)
    (match value ((Token _) (unit)))))

(define main
  (lambda ()
    (let ((token (new Token (id 1))))
      (unit))
    (unit)))
