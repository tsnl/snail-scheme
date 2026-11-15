(import
 (snail core base)
 (only (snail core forms) Host)
 (snail core io)
 (snail shell task))

(record Task-value
  ((value I64)))

(define (main) (→ Unit) (! Host Mut Output-port Tasks)

  (let ((cell (new Task-value (value 0))))
    (dispatch
     (lambda ()
       (set! (● cell value) 42)
       (yield)
       (display (● cell value))
       (newline))))
  (unit))
