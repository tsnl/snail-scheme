(import
 (snail core base)
 (snail core io))

;; The implementation performs a control effect, Log, and so does
;; `resume`: each later yield runs the implementation again where `resume`
;; is called. `next` says Log, so calling it is a yield point, and the
;; second log reaches the handler in scope there, the outer one, since
;; `logged` has returned.
(effect Gen
  ((ctl yield (Fn I64 → I64))))

(effect Log
  ((ctl log (Fn String → Unit))))

(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (FnOnce I64 → Step ! Log)))))

(define (start (body (Fn → Unit ! Gen))) (→ Step) (! Log)
  (handle Gen ((yield (lambda (v resume)
                        (log (string-append "handler saw " (show v)))
                        (Yielded v resume))))
    (body)
    (Done)))

(define (counter) (→ Unit) (! Gen)
  (yield 1)
  (yield 2)
  (unit))

(define (logged (body (Fn → Step ! Log))) (→ Step) (! output-port)
  (handle Log ((log (lambda (line resume) (write-line line) (resume (unit)))))
    (body)))

(define (run) (→ Unit) (! output-port)
  (handle Log ((log
                (lambda (line resume) (write-line (string-append "outer: " line)) (resume (unit)))))
    (match (logged (lambda () (start counter)))
      ((Yielded value next)
       (write-line (string-append "got " (show value)))
       (let ((step (next 10)))
         (write-line "after next")
         (match step
           ((Yielded value rest)
            (drop rest)
            (write-line (string-append "got " (show value))))
           ((Done) (write-line "done")))))
      ((Done) (write-line "done at once")))))

(define (main) (→ Unit) (! output-port)
  (run)
  (unit))
