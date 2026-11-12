(import
 (snail core base)
 (snail core io)
 (snail shell task))

(struct TaskValue
  ((value I64)))

(define main
  (lambda ()
    (let ((cell (TaskValue 0)))
      (dispatch-local
       (once (lambda ()
               (set! (● cell value) 42)
               (yield)
               (display (● cell value))
               (newline)))))
    (unit)))
