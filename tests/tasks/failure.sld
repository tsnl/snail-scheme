(import
 (snail core base)
 (snail core io)
 (only (snail core forms) host)
 (snail shell task))

(define (main) (→ Unit) (! tasks mut host output-port)
  (dispatch-local (once (lambda () (panic "child failed"))))
  (dispatch-local (once (lambda () (yield) (write-line "survived"))))
  (unit))
