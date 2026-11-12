(import
 (snail core base)
 (snail core io)
 (snail shell task))

(define main
  (lambda ()
    (dispatch-local (once (lambda () (panic "child failed"))))
    (dispatch-local (once (lambda () (yield) (write-line "survived"))))
    (unit)))
