(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (snail shell task))

(struct TaskValue
  ((value I64)))

(define (main) (→ Unit) (! host mut output-port tasks)

  (let ((cell (TaskValue 0)))
    (dispatch-local
     (once (lambda ()
             (set! (● cell value) 42)
             (yield)
             (display (● cell value))
             (newline)))))
  (unit))
