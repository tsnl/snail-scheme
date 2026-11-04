(import
 (snail core base)
 (snail core io))

(struct Resource
  ((value I64)))
(define-instance-set cleanup
  (instance (Drop (!) Resource)
    (define (drop value) (unit))))
