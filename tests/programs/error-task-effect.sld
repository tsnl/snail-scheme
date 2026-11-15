(import
 (snail core base)
 (snail shell task))

(effect Missing ((missing (Fn → Unit))))

(define main
  (lambda ()
    (dispatch (lambda () (missing)))
    (unit)))
