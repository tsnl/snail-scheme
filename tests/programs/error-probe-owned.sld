(import
 (snail core base))

(struct Owned
  ((value I64)))

(instance (Drop (!) Owned)
  (define drop (lambda (value) (match value ((Owned _) (unit))))))

(define main
  (lambda ()
    (match (try-convert (ann #f Any) Owned)
      ((Ok value) (drop value))
      (_ (unit)))
    (unit)))
