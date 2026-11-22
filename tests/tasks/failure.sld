(import
 (snail core base)
 (snail core io)
 (snail shell task))

(define (main (out OutputPort)) (→ Unit)
  (dispatch (lambda () (panic "child failed")))
  (dispatch (lambda () (yield) (write-line out "survived")))
  (unit))
