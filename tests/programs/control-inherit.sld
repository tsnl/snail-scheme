(import
 (snail core base)
 (snail core io)
 (only (snail core forms) host)
 (only (snail core primitive) inherit-handlers))

;; `inherit-handlers` closes a procedure over the handlers in scope where
;; it is called, so the procedure reaches them wherever it is later
;; called, even after their handles have returned. The function it makes
;; performs `host`, as code may that runs whatever the host implements,
;; which a program's top level may. The book's chapter on effects includes
;; the text between each ANCHOR and ANCHOR_END.
(effect Log
  ((log (Fn String → Unit))))

(define (first-log (out OutputPort) (line String)) (→ Unit) (! mut)
  (write-line out (string-append "first log: " line)))

(define (second-log (out OutputPort) (line String)) (→ Unit) (! mut)
  (write-line out (string-append "second log: " line)))

;; ANCHOR_END: thunk

;; A resumption stored and resumed later under another log, as in
;; control-stored-resume, logs to that one. A thunk that resumes it, closed
;; over the handlers where the generator yielded, logs to the log in scope
;; there, as a task scheduler's steps must.
(effect Gen
  ((ctl yield (Fn I64 → Unit))))

;; ANCHOR: resume
(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (Fn → Step ! host)))))

(define (start (body (Fn → Unit ! Gen Log))) (→ Step) (! Log)
  (handle Gen ((yield (lambda (value resume)
                        (Yielded value (inherit-handlers (lambda () (resume (unit))))))))
    (body)
    (Done)))

;; ANCHOR_END: resume

(define (count-to (value I64) (last I64)) (→ Unit) (! Gen Log)
  (when (<= value last)
    (log (string-append "produces " (show value)))
    (yield value)
    (count-to (+ value 1) last)))

(define (drain (out OutputPort) (step Step)) (→ Unit) (! mut host)
  (match step
    ((Done) (write-line out "done"))
    ((Yielded value next)
     (write-line out (string-append "got " (show value)))
     (drain out (next)))))

(define (main (out OutputPort)) (→ Unit) (! host mut)
  ;; ANCHOR: thunk
  ;; A thunk closed under the first log runs under the second, and logs to
  ;; the first.
  (let ((work (handle Log ((log (lambda (line) (first-log out line))))
                (inherit-handlers (lambda () (log "a thunk"))))))
    (handle Log ((log (lambda (line) (second-log out line))))
      (log "before the thunk")
      (work)))
  (let ((step (handle Log ((log (lambda (line) (first-log out line))))
                (start (lambda () (count-to 1 2))))))
    (handle Log ((log (lambda (line) (second-log out line))))
      (log "draining")
      (drain out step)))
  (unit))
