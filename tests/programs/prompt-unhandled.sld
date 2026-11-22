(import
 (snail core base)
 (snail core io))

;; A suspension needs a `with-prompt` of its prompt around it. With none
;; running, nothing could catch it, so `suspend` panics where it is called:
;; here the `with-prompt` has returned by the time the function it made is
;; called.
(define pausing (→ (Prompt Unit Unit)) (make-prompt))

(define (later) (→ (Fn → Unit))
  (with-prompt pausing
               (lambda () (lambda () (suspend pausing (unit))))
               (lambda (value resume) (lambda () (unit)))))

(define (main (out OutputPort)) (→ Unit)
  (write-line out "made")
  ((later))
  (write-line out "not reached")
  (unit))
