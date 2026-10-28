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
  ((ctl await (-> I64 I64))
   (task-id (-> I64))))

(effect Io
  ((fetch (-> I64 I64 ! Async))))
;; ANCHOR_END: effects

;; ANCHOR: tasks
;; A task's step: done, or waiting on a ticket with the rest of the task,
;; to be resumed once with the ticket's answer.
(enum Task
  (Done
   ((value I64)))
  (Waiting
   ((ticket I64)
    (next (Once (-> I64 Task ! Io console))))))

;; Runs a task to its first wait under its own handler, which hands back
;; the rest of the task rather than resuming it.
(: start (-> I64 (-> I64 ! Io Async console) Task ! Io console))
(define (start id body)
  (handle Async
      ((await (lambda (ticket resume) (Waiting ticket resume)))
       (task-id (lambda () id)))
    (Done (body))))

;; Two fetches, the second after the first has been answered.
(: job (-> I64 I64 ! Io Async console))
(define (job first)
  (let ((answer (fetch first)))
    (write-line (string-append "fetched " (show answer)))
    (+ answer (fetch (+ first 1)))))
;; ANCHOR_END: tasks

;; Answers each wait with ten times its ticket, alternating between the
;; tasks, long after their handlers returned.
(: alternate (-> Task Task Unit ! Io console))
(define (alternate this other)
  (match this
    ((Done value)
     (write-line (string-append "done with " (show value)))
     (drive other))
    ((Waiting ticket next)
     (write-line (string-append "waiting on " (show ticket)))
     (alternate other (next (* ticket 10))))))

(: drive (-> Task Unit ! Io console))
(define (drive task)
  (match task
    ((Done value) (write-line (string-append "done with " (show value))))
    ((Waiting ticket next)
     (write-line (string-append "waiting on " (show ticket)))
     (drive (next (* ticket 10))))))

;; ANCHOR: io
;; Io's handler is outside both tasks' handlers, yet its fetch asks the
;; performing task for its id and waits on that task's scheduler.
(handle Io
    ((fetch (lambda (ticket)
              (write-line (string-append "task " (show (task-id)) " fetches " (show ticket)))
              (+ (await ticket) 1))))
  (alternate (start 1 (lambda () (job 10))) (start 2 (lambda () (job 20)))))
;; ANCHOR_END: io

;; ANCHOR: notes
;; An ordinary effect in a latent row goes to the performer's handler
;; too: note's implementation logs where note is performed.
(effect Log
  ((log (-> String Unit))))

(effect Notes
  ((note (-> String Unit ! Log))))

(handle Log ((log (lambda (line) (write-line (string-append "outer log: " line)))))
  (handle Notes ((note (lambda (text) (log (string-append "note " text)))))
    (log "before")
    (handle Log ((log (lambda (line) (write-line (string-append "inner log: " line)))))
      (note "inside"))))
;; ANCHOR_END: notes
