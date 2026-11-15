(import
 (snail core base)
 (snail core io)
 (only (snail core forms) host)
 (snail shell task))

(define (main) (→ Unit) (! tasks mut host output-port)
  (dispatch (lambda () (panic "child failed")))
  (dispatch (lambda () (yield) (write-line "survived")))
  (unit))
