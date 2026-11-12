(import
 (snail core base)
 (snail core io))

;; The implementation performs a control effect, Log, which `resume`
;; performs too, since each later yield runs the implementation again
;; where `resume` is called. Were `next` typed without Log, its call would
;; not be a yield point, and the resumer would run on with a placeholder
;; Step while the yield went on to the Log handler around it.
(effect Gen
  ((ctl yield (dyn (Fn I64 → I64)))))

(effect Log
  ((ctl log (dyn (Fn String → Unit)))))

(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (dyn (FnOnce I64 → Step))))))

(define (start (body (dyn (Fn → Unit ! Gen)))) (→ Step) (! Log)
  (handle Gen ((yield (lambda (v resume)
                        (log (string-append "handler saw " (show v)))
                        (Yielded v resume))))
    (body)
    (Done)))

(define (counter) (→ Unit) (! Gen)
  (yield 1)
  (yield 2)
  (unit))

(define (logged (body (dyn (Fn → Step ! Log)))) (→ Step) (! output-port)
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
           ((Yielded value _) (write-line (string-append "got " (show value))))
           ((Done) (write-line "done")))))
      ((Done) (write-line "done at once")))))

(run)
