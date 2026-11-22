(import
 (snail core base)
 (snail core io))

;; An ordinary operation's type may name the control effects its
;; implementations perform, as `fetch` names Async: performing it charges
;; the caller Async too, and its implementation's Async operations go to
;; the handler in scope where it was performed, not to one outside Io's
;; handler. So each task's fetch waits on that task's own scheduler.
;; ANCHOR: effects
(effect Async
  ((ctl await (Fn I64 → I64))
   (task-id (Fn → I64))))

(effect Io
  ((fetch (Fn I64 → I64 ! Async))))

;; ANCHOR_END: effects

;; ANCHOR: tasks
;; A task's step: done, or waiting on a ticket with the rest of the task,
;; to be resumed once with the ticket's answer.
(enum Task
  (Done
   ((value I64)))
  (Waiting
   ((ticket I64)
    (next (Fn I64 → Task ! Io mut)))))

;; Runs a task to its first wait under its own handler, which hands back
;; the rest of the task rather than resuming it.
(define (start (out OutputPort) (id I64) (body (Fn → I64 ! Io Async mut))) (→ Task) (! Io mut)
  (handle Async
      ((await (lambda (ticket resume) (Waiting ticket resume)))
       (task-id (lambda () id)))
    (Done (body))))

;; Two fetches, the second after the first has been answered.
(define (job (out OutputPort) (first I64)) (→ I64) (! Io Async mut)
  (let ((answer (fetch first)))
    (write-line out (string-append "fetched " (show answer)))
    (+ answer (fetch (+ first 1)))))

;; ANCHOR_END: tasks

;; Answers each wait with ten times its ticket, alternating between the
;; tasks, long after their handlers returned.
(define (alternate (out OutputPort) (this Task) (other Task)) (→ Unit) (! Io mut)
  (match this
    ((Done value)
     (write-line out (string-append "done with " (show value)))
     (drive out other))
    ((Waiting ticket next)
     (write-line out (string-append "waiting on " (show ticket)))
     (alternate out other (next (* ticket 10))))))

(define (drive (out OutputPort) (task Task)) (→ Unit) (! Io mut)
  (match task
    ((Done value) (write-line out (string-append "done with " (show value))))
    ((Waiting ticket next)
     (write-line out (string-append "waiting on " (show ticket)))
     (drive out (next (* ticket 10))))))

;; ANCHOR_END: io

;; ANCHOR: notes
;; An ordinary effect in a latent row goes to the performer's handler
;; too: note's implementation logs where note is performed.
(effect Log
  ((log (Fn String → Unit))))

(effect Notes
  ((note (Fn String → Unit ! Log))))

(define (main (out OutputPort)) (→ Unit) (! mut)
  ;; ANCHOR: io
  ;; Io's handler is outside both tasks' handlers, yet its fetch asks the
  ;; performing task for its id and waits on that task's scheduler.
  (handle Io
      ((fetch (lambda (ticket)
                (write-line out (string-append "task " (show (task-id)) " fetches " (show ticket)))
                (+ (await ticket) 1))))
    (alternate out (start out 1 (lambda () (job out 10))) (start out 2 (lambda () (job out 20)))))
  (handle Log ((log (lambda (line) (write-line out (string-append "outer log: " line)))))
    (handle Notes ((note (lambda (text) (log (string-append "note " text)))))
      (log "before")
      (handle Log ((log (lambda (line) (write-line out (string-append "inner log: " line)))))
        (note "inside"))))
  (unit))
