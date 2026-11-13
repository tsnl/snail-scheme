(import
 (snail core base))

(define (main)
  (→ Unit)
  (! mut)
  (let ((memo (cache (lambda (key) (rc-get key))))) (memo (rc 42)) (unit)))
