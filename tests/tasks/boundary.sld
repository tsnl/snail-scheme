(import
 (lofi base)
 (lofi io)
 (lofi task))
(dispatch-local (once (lambda () (write-line "ran"))))
(dispatch-local (once (lambda () (write-line "discarded work ran"))))
