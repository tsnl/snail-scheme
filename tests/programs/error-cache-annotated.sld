(import
 (snail core base))

(define (main) (→ Unit) (! mut)
  (let ((memo ((ann cache (Fn (Fn → (Rc I64)) → (Fn → (Rc I64)))) (lambda () (rc 42)))))
    (memo) (unit)))
