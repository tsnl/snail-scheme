(import
 (snail core base))

(record Box
  ((value (Option (Rc I64)))))
(define (main) (→ Unit) (! mut)
  (let ((memo (cache (lambda () (new Box (value (None))))))) (memo) (unit)))
