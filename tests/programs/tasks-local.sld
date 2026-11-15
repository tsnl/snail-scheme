(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (snail shell task))

(record TaskValue
  ((value I64)))

(define (main) (→ Unit) (! host mut output-port tasks)

  (let ((cell (new TaskValue (value 0))))
    (dispatch
     (lambda ()
       (set! (● cell value) 42)
       (yield)
       (display (● cell value))
       (newline))))
  (unit))
