(import
 (snail core base))

(struct Owned
  ((value I64)))
(instance (Drop (!) Owned)
  (define (drop value) (match value ((Owned _) (unit)))))

(match (try-convert (ann #f Any) Owned)
  ((Ok value) (drop value))
  (_ (unit)))
