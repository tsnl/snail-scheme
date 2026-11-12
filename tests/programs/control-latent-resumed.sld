(import
 (snail core base)
 (snail core io))

;; An implementation's latent operations after a `resume`, when the task
;; is resumed somewhere else (#565). They still go to the handlers where
;; the operation was performed, as the resume left them: the task's own
;; handler, re-installed, and beyond it the handlers in scope where the
;; task was resumed. So `fetch` asks task 1 whose task it is although task
;; 2 resumed it, and logs to the log around the resume, not to the one
;; around the task when `fetch` was performed.
(effect Async
  ((ctl await (Fn I64 → I64))
   (task-id (Fn → I64))))

(effect Log
  ((log (Fn String → Unit))))

(effect Io
  ((fetch (Fn I64 → I64 ! Async Log))))

(enum Task
  (Done
   ((value I64)))
  (Waiting
   ((ticket I64)
    (next (FnOnce I64 → Task ! Io Log)))))

(define (start (id I64) (body (FnOnce → I64 ! Io Async Log))) (→ Task) (! Io Log)
  (handle Async
      ((await (lambda (ticket resume)
                (log (string-append "task " (show id) " waits on " (show ticket)))
                (Waiting ticket resume)))
       (task-id (lambda () id)))
    (Done (body))))

;; Answers each wait with its ticket.
(define (finish (task Task)) (→ I64) (! Io Log)
  (match task
    ((Done value) value)
    ((Waiting ticket next) (finish (next ticket)))))

(define (labelled (name String) (line String)) (→ Unit) (! output-port)
  (write-line (string-append name ": " line)))

(handle Io
    ((fetch (lambda (ticket)
              (log (string-append "fetch in task " (show (task-id))))
              (let ((answer (await ticket)))
                (log (string-append "fetch resumed in task " (show (task-id))))
                (await (+ answer 1))))))
  (let ((first (handle Log ((log (lambda (line) (labelled "the first log" line))))
                 (start 1 (once (lambda () (fetch 1)))))))
    (handle Log ((log (lambda (line) (labelled "the second log" line))))
      (match first
        ((Waiting ticket next)
         ;; Task 1's first wait is answered inside task 2.
         (write-line (show (finish (start 2 (once (lambda ()
                                                    (log (string-append "task "
                                                                        (show (task-id))
                                                                        " resumes task 1"))
                                                    (finish (next (* ticket 10))))))))))
        ((Done value) (write-line (show value)))))))
