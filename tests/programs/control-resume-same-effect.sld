(import
 (snail core base)
 (snail core io))

;; A deep handler stays with its computation. A stored resumption called
;; under a second handler of the same effect still yields to the first,
;; which resuming re-installed around the rest of the body; only what the
;; second handle's own body yields reaches the second.
(effect Gen
  ((ctl yield (Fn I64 → Unit))))

(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (Fn Unit → Step)))))

(define (start (body (Fn → Unit ! Gen))) (→ Step)
  (handle Gen ((yield (lambda (value resume) (Yielded value resume))))
    (body)
    (Done)))

(define (count (first I64) (last I64)) (→ Unit) (! Gen)
  (when (<= first last)
    (yield first)
    (count (+ first 1) last)))

;; Yields once to a second handler, which announces and resumes it, then
;; resumes the generator under that handler.
(define (under-second (out OutputPort) (next (Fn Unit → Step))) (→ Step) (! mut)
  (handle Gen ((yield (lambda (value resume)
                        (write-line out (string-append "second handler: " (show value)))
                        (resume (unit)))))
    (yield 0)
    (next (unit))))

(define (drain (out OutputPort) (step Step)) (→ Unit) (! mut)
  (match step
    ((Done) (write-line out "done"))
    ((Yielded value next)
     (write-line out (string-append "first handler: " (show value)))
     (drain out (under-second out next)))))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (drain out (start (lambda () (count 1 3))))
  (unit))
