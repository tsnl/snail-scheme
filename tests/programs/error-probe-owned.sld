(import
 (snail core base))

(struct Owned
  ((value I64)))

(instance (Drop (!) Owned)
  (define (drop (value Owned)) (→ Unit)
    (match value ((Owned _) (unit)))))

(define main
  (lambda ()
    (match (downcast Owned (Any #f))
      ((Some value) (drop value))
      (_ (unit)))
    (unit)))
