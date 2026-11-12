(import
 (snail core base)
 (snail core io))

;; A deep handler stays with its computation. A stored resumption called
;; under a second handler of the same effect still yields to the first,
;; which resuming re-installed around the rest of the body; only what the
;; second handle's own body yields reaches the second.
(effect Gen
  ((ctl yield (dyn (Fn I64 → Unit)))))

(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (dyn (FnOnce Unit → Step))))))

(define (start (body (dyn (Fn → Unit ! Gen)))) (→ Step)
  (handle Gen ((yield (lambda (value resume) (Yielded value resume))))
    (body)
    (Done)))

(define (count (first I64) (last I64)) (→ Unit) (! Gen)
  (when (<= first last)
    (yield first)
    (count (+ first 1) last)))

;; Yields once to a second handler, which announces and resumes it, then
;; resumes the generator under that handler.
(define (under-second (next (dyn (FnOnce Unit → Step)))) (→ Step) (! output-port)
  (handle Gen ((yield (lambda (value resume)
                        (write-line (string-append "second handler: " (show value)))
                        (resume (unit)))))
    (yield 0)
    (next (unit))))

(define (drain (step Step)) (→ Unit) (! output-port)
  (match step
    ((Done) (write-line "done"))
    ((Yielded value next)
     (write-line (string-append "first handler: " (show value)))
     (drain (under-second next)))))

(drain (start (lambda () (count 1 3))))
