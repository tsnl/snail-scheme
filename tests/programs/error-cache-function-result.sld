(import
 (snail core base))

(define (main) (→ Unit)
  (let ((memo (cache (lambda () (lambda (x) (+ x 1)))))) (memo) (unit)))
