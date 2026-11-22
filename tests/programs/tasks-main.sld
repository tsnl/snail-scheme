(import
 (snail core base)
 (snail core io)
 (snail shell task))

(define (main (out OutputPort)) (→ Unit) (! mut)
  ;; A program's statements run as its first task, so they may yield, sleep
  ;; and wait like any task's: a child dispatched first runs when the body
  ;; yields, and the body resumes after it.
  (dispatch (lambda () (write-line out "the child runs when main yields")))
  (write-line out "main starts")
  (yield)
  (write-line out "main resumes")
  (sleep 1)
  (write-line out "main ends")
  (unit))
