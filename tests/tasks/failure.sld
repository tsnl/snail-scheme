(import
 (snail core base)
 (snail core io)
 (snail shell task))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (dispatch (lambda () (panic "child failed")))
  (dispatch (lambda () (yield) (write-line out "survived")))
  (unit))
