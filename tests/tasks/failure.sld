(import
 (snail core base)
 (snail core io)
 (only (snail core forms) Host)
 (snail shell task))

(define (main) (→ Unit) (! Tasks Mut Host Output-port)
  (dispatch (lambda () (panic "child failed")))
  (dispatch (lambda () (yield) (write-line "survived")))
  (unit))
