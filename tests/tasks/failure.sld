(import
 (lofi base)
 (lofi io)
 (lofi task))
(dispatch-local (once (lambda () (panic "child failed"))))
(dispatch-local (once (lambda () (yield) (write-line "survived"))))
