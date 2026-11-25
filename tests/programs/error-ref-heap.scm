(import
 (snail core base))

(record Nested
  ((values (Array I64))))
(define (main) (→ Unit) (let ((x (ref-local (new Nested (values (make-array 1 0)))))) (unit)))
