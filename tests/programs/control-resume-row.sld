(import
 (snail core base)
 (snail core io))

;; `resume` performs the handle's context row, so a stored resumption says
;; Log, and is resumed under a Log handler: the one in scope where it is
;; called, not the one around `start`.
(effect Gen
  ((ctl yield (Fn I64 → I64))))

(effect Log
  ((log (Fn String → Unit))))

(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (Fn I64 → Step ! Log)))))

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

(define (main) (→ Unit) (! output-port)
  ;; Each handler prints the lines it is given under its own name.
  (match (handle Log ((log (lambda (line) (write-line (string-append "first: " line)))))
           (start counter))
    ((Yielded value next)
     (write-line (string-append "got " (show value)))
     (handle Log ((log (lambda (line) (write-line (string-append "second: " line)))))
       (match (next 10)
         ((Yielded value _)
          (write-line (string-append "got " (show value))))
         ((Done) (write-line "done")))))
    ((Done) (write-line "done at once")))
  (unit))
