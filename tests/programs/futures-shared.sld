(import
 (only (snail core forms) host)
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell future)
 (snail shell async))

;; Any number of tasks may await one future, and each wakes once it is
;; ready, in the order they began waiting.
(define (main) (→ Unit) (! host mut output-port completion tasks)
  (let ((shared (dispatch (lambda () (yield) "ready"))))
    (dispatch-local (lambda () (write-line (string-append "first " (await-future shared)))))
    (dispatch-local (lambda () (write-line (string-append "second " (await-future shared))))))
  (unit))
