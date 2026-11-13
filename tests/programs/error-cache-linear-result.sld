(import
 (snail core base))

(struct Resource
  ((value I64)))
(instance (Drop (!) Resource)
  (define (drop (value Resource)) (→ Unit) (match value ((Resource _) (unit)))))
(define (main) (→ Unit)
  (let ((memo (cache (lambda () (Resource 1))))) (drop (memo))))
