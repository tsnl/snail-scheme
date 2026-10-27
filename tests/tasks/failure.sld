(import
 (snail-core base)
 (snail-core io)
 (snail-core task))
(dispatch-local (once (lambda () (panic "child failed"))))
(dispatch-local (once (lambda () (yield) (write-line "survived"))))
