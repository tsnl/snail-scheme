(import
 (snail core base)
 (snail core io)
 (only (snail core forms) host)
 (snail shell task))

(define (main (out OutputPort)) (→ Unit) (! tasks mut host)
  (dispatch (lambda () (panic "child failed")))
  (dispatch (lambda () (yield) (write-line out "survived")))
  (unit))
