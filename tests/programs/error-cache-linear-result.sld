(import
 (snail core base))

(record Resource
  ((value I64)))
(instance (Drop (!) Resource)
  (define (drop (value Resource)) (→ Unit) (match value ((Resource _) (unit)))))
(define (main) (→ Unit)
  (let ((memo (cache (lambda () (new Resource (value 1)))))) (drop (memo))))
