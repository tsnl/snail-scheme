(import
 (snail core base))

(define (main)
  (→ Unit)
  (! mut)
  (let ((memo (unsafe-effectful-cache (lambda (key) (rc-get key))))) (memo (rc 42)) (unit)))
