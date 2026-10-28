(import
 (snail core base)
 (snail core io))

;; The implementation performs a control effect, Log, which `resume`
;; performs too, since each later yield runs the implementation again
;; where `resume` is called. Were `next` typed without Log, its call would
;; not be a yield point, and the resumer would run on with a placeholder
;; Step while the yield went on to the Log handler around it.
(effect Gen
  ((ctl yield (-> I64 I64))))

(effect Log
  ((ctl log (-> String Unit))))

(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (Once (-> I64 Step))))))

(: start (-> (-> Unit ! Gen) Step ! Log))
(define (start body)
  (handle Gen ((yield (lambda (v resume)
                        (log (string-append "handler saw " (show v)))
                        (Yielded v resume))))
    (body)
    (Done)))

(: counter (-> Unit ! Gen))
(define (counter)
  (yield 1)
  (yield 2)
  (unit))

(: logged (-> (-> Step ! Log) Step ! console))
(define (logged body)
  (handle Log ((log (lambda (line resume) (write-line line) (resume (unit)))))
    (body)))

(: run (-> Unit ! console))
(define (run)
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
