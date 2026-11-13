(import
 (snail core base))

(struct Box
  ((value (Option (Rc I64)))))
(define (main) (→ Unit) (! mut)
  (let ((memo (cache (lambda () (Box (None)))))) (memo) (unit)))
