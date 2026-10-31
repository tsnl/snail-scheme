(import
 (snail core base)
 (snail core io))

;; A deep handler stays with its computation. A stored resumption called
;; under a second handler of the same effect still yields to the first,
;; which resuming re-installed around the rest of the body; only what the
;; second handle's own body yields reaches the second.
(effect Gen
  ((ctl yield (-> I64 Unit))))

(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (FnOnce Unit Step)))))

(: start (-> (-> Unit ! Gen) Step))
(define (start body)
  (handle Gen ((yield (lambda (value resume) (Yielded value resume))))
    (body)
    (Done)))

(: count (-> I64 I64 Unit ! Gen))
(define (count first last)
  (when (<= first last)
    (yield first)
    (count (+ first 1) last)))

;; Yields once to a second handler, which announces and resumes it, then
;; resumes the generator under that handler.
(: under-second (-> (FnOnce Unit Step) Step ! console))
(define (under-second next)
  (handle Gen ((yield (lambda (value resume)
                        (write-line (string-append "second handler: " (show value)))
                        (resume (unit)))))
    (yield 0)
    (next (unit))))

(: drain (-> Step Unit ! console))
(define (drain step)
  (match step
    ((Done) (write-line "done"))
    ((Yielded value next)
     (write-line (string-append "first handler: " (show value)))
     (drain (under-second next)))))

(drain (start (lambda () (count 1 3))))
