(import
 (snail core base)
 (snail core io)
 (snail shell task))

;; A task waits wherever it is: inside a callback an ordinary function
;; calls, inside a generator's body, inside a handler. Nothing between the
;; wait and the task says so in its type.
(define yielding (→ (Prompt I64 Unit)) (make-prompt))

(define (collect (body (Fn → Unit ! mut))) (→ (List I64)) (! mut)
  (with-prompt yielding
               (lambda ()
                 (body)
                 (Nil))
               (lambda (value resume) (Cons value (resume (unit))))))

(define (worker (out OutputPort) (name String) (items (List I64))) (→ Unit) (! mut)
  ;; `for-each` knows nothing of tasks, and its callback sleeps.
  (for-each (lambda (item)
              (sleep item)
              (write-line out (string-append name " slept " (show item))))
            items)
  ;; The generator's body yields to its collector and waits as a task
  ;; between values: the collector is kept with the rest of the task.
  (write-line out
              (string-append name
                             " collected "
                             (repr (collect (lambda ()
                                              (suspend yielding 1)
                                              (yield)
                                              (suspend yielding 2)))))))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (dispatch (lambda () (worker out "first" (list 1 30))))
  (dispatch (lambda () (worker out "second" (list 10 20))))
  (write-line out "main returns")
  (unit))
