(import
 (snail core base)
 (snail core io)
 (snail shell task))

(record TaskValue
  ((value I64)))

(define (main (out OutputPort)) (→ Unit)

  (let ((cell (new TaskValue (value 0))))
    (dispatch
     (lambda ()
       (set! (● cell value) 42)
       (yield)
       (display out (● cell value))
       (newline out))))
  (unit))
