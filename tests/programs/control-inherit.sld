(import
 (snail core base)
 (snail core io)
 (only (snail core forms) host)
 (only (snail core primitive) inherit-handlers inherit-handlers-1))

;; `inherit-handlers` closes a one-shot procedure over the handlers in
;; scope where it is called, so the procedure reaches them wherever it is
;; later called, even after their handles have returned. The FnOnce it makes
;; performs `host`, as code may that runs whatever the host implements,
;; which a program's top level may. The book's chapter on effects includes
;; the text between each ANCHOR and ANCHOR_END.
(effect Log
  ((log (-> String Unit))))

(: first-log (-> String Unit ! console))
(define (first-log line)
  (write-line (string-append "first log: " line)))

(: second-log (-> String Unit ! console))
(define (second-log line)
  (write-line (string-append "second log: " line)))

;; ANCHOR: thunk
;; A thunk closed under the first log runs under the second, and logs to
;; the first.
(let ((work (handle Log ((log first-log))
              (inherit-handlers (once (lambda () (log "a thunk")))))))
  (handle Log ((log second-log))
    (log "before the thunk")
    (work)))
;; ANCHOR_END: thunk

;; A resumption is a procedure of one argument. Stored and resumed later
;; under another log, as in control-stored-resume, it logs to that one;
;; closed over its handlers first, it logs to the one in scope where the
;; generator yielded, as a task scheduler's steps must.
(effect Gen
  ((ctl yield (-> I64 Unit))))

;; ANCHOR: resume
(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (FnOnce Unit Step ! host)))))

(: start (-> (-> Unit ! Gen Log) Step ! Log))
(define (start body)
  (handle Gen ((yield (lambda (value resume) (Yielded value (inherit-handlers-1 resume)))))
    (body)
    (Done)))
;; ANCHOR_END: resume

(: count-to (-> I64 I64 Unit ! Gen Log))
(define (count-to value last)
  (when (<= value last)
    (log (string-append "produces " (show value)))
    (yield value)
    (count-to (+ value 1) last)))

(: drain (-> Step Unit ! console host))
(define (drain step)
  (match step
    ((Done) (write-line "done"))
    ((Yielded value next)
     (write-line (string-append "got " (show value)))
     (drain (next (unit))))))

(let ((step (handle Log ((log first-log))
              (start (lambda () (count-to 1 2))))))
  (handle Log ((log second-log))
    (log "draining")
    (drain step)))
