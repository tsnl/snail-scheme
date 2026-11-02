(import
 (snail core base)
 (snail core io)
 (snail shell task))

;; A program's statements run as its first task, so they may yield, sleep
;; and wait like any task's: a child dispatched first runs when the body
;; yields, and the body resumes after it.
(dispatch-local (once (lambda () (write-line "the child runs when main yields"))))
(write-line "main starts")
(yield)
(write-line "main resumes")
(sleep 1)
(write-line "main ends")
