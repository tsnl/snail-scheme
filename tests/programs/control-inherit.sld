(import
 (snail core base)
 (snail core io)
 (only (snail core forms) host)
 (only (snail core primitive) inherit-handlers inherit-handlers-1))

;; `inherit-handlers` closes a procedure over the handlers in scope where
;; it is called, so the procedure reaches them wherever it is later
;; called, even after their handles have returned. The function it makes
;; performs `host`, as code may that runs whatever the host implements,
;; which a program's top level may. The book's chapter on effects includes
;; the text between each ANCHOR and ANCHOR_END.
(effect Log
  ((log (Fn String → Unit))))

(define (first-log (line String)) (→ Unit) (! output-port)
  (write-line (string-append "first log: " line)))

(define (second-log (line String)) (→ Unit) (! output-port)
  (write-line (string-append "second log: " line)))

;; ANCHOR_END: thunk

;; A resumption is a procedure of one argument. Stored and resumed later
;; under another log, as in control-stored-resume, it logs to that one;
;; closed over its handlers first, it logs to the one in scope where the
;; generator yielded, as a task scheduler's steps must.
(effect Gen
  ((ctl yield (Fn I64 → Unit))))

;; ANCHOR: resume
(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (Fn Unit → Step ! host)))))

(define (start (body (Fn → Unit ! Gen Log))) (→ Step) (! Log)
  (handle Gen ((yield (lambda (value resume) (Yielded value (inherit-handlers-1 resume)))))
    (body)
    (Done)))

;; ANCHOR_END: resume

(define (count-to (value I64) (last I64)) (→ Unit) (! Gen Log)
  (when (<= value last)
    (log (string-append "produces " (show value)))
    (yield value)
    (count-to (+ value 1) last)))

(define (drain (step Step)) (→ Unit) (! output-port host)
  (match step
    ((Done) (write-line "done"))
    ((Yielded value next)
     (write-line (string-append "got " (show value)))
     (drain (next (unit))))))

(define (main) (→ Unit) (! host output-port)
  ;; ANCHOR: thunk
  ;; A thunk closed under the first log runs under the second, and logs to
  ;; the first.
  (let ((work (handle Log ((log first-log))
                (inherit-handlers (lambda () (log "a thunk"))))))
    (handle Log ((log second-log))
      (log "before the thunk")
      (work)))
  (let ((step (handle Log ((log first-log))
                (start (lambda () (count-to 1 2))))))
    (handle Log ((log second-log))
      (log "draining")
      (drain step)))
  (unit))
