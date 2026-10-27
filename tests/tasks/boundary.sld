(import
 (snail-core base)
 (snail-core io)
 (snail-core task))
(dispatch-local (once (lambda () (write-line "ran"))))
(dispatch-local (once (lambda () (write-line "discarded work ran"))))
