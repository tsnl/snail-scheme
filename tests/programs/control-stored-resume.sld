(import
 (snail core base)
 (snail core io))

;; `resume` is a value: a handler can return it instead of calling it, and
;; whoever holds it resumes the computation later, after the handler has
;; returned, under whatever handlers are in scope where it is called.
(effect Gen
  ((ctl yield (Fn I64 → Unit))))

(effect Log
  ((log (Fn String → Unit))))

;; A step of a generator: done, or a value and the rest, which may be
;; resumed once; a second resume panics.
(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (Fn Unit → Step ! Log)))))

;; The generator's first step: the handler hands back each value with the
;; rest of the body still to run.
(define (start (body (Fn → Unit ! Gen Log))) (→ Step) (! Log)
  (handle Gen ((yield (lambda (value resume) (Yielded value resume))))
    (body)
    (Done)))

(define (count-from (name String) (first I64) (count I64)) (→ Unit) (! Gen Log)
  (when (> count 0)
    (log (string-append name " produces " (show first)))
    (yield first)
    (count-from name (+ first 1) (- count 1))))

(record Pair-of-steps
  ((left Step)
   (right Step)))

;; Both generators take their first step under one log.
(define (begin-both) (→ Pair-of-steps) (! output-port)
  (handle Log ((log (lambda (line) (write-line (string-append "first log: " line)))))
    (new Pair-of-steps (left (start (lambda () (count-from "a" 1 3))))
         (right (start (lambda () (count-from "b" 10 2)))))))

;; The rest alternates between them, long after their handlers returned,
;; under another log: each resumed step logs to the handler in scope here.
(define (alternate (this Step) (other Step)) (→ Unit) (! Log output-port)
  (match this
    ((Done)
     (match other
       ((Done) (write-line "both done"))
       (rest (alternate rest (Done)))))
    ((Yielded value next)
     (write-line (string-append "got " (show value)))
     (alternate other (next (unit))))))

;; A control effect in the resumed part: the generator asks for a scale
;; with a control operation, which the handler in scope where it is
;; resumed answers. The node of the generator's handler takes the
;; resumer's evidence as its outside, so the yield reaches that handler,
;; not the one that was in scope when the generator started.
(effect Ask
  ((ctl ask (Fn → I64))))

(enum Asking
  (Finished)
  (Gave
   ((value I64)
    (next (Fn Unit → Asking ! Ask)))))

(define (scaled (count I64)) (→ Asking) (! Ask)
  (handle Gen ((yield (lambda (value resume) (Gave value resume))))
    (let loop ((index 1))
      (when (<= index count)
        (yield (* index (ask)))
        (loop (+ index 1))))
    (Finished)))

(define (drain (step Asking) (scale I64)) (→ Unit) (! output-port)
  (match step
    ((Finished) (write-line "finished"))
    ((Gave value next)
     (write-line (string-append "gave " (show value)))
     (drain (handle Ask ((ask (lambda (resume) (resume scale)))) (next (unit))) (* scale 10)))))

(define (main) (→ Unit) (! output-port)
  (match (begin-both)
    ((Pair-of-steps left right)
     (handle Log ((log (lambda (line) (write-line (string-append "second log: " line)))))
       (alternate left right))))
  (drain (handle Ask ((ask (lambda (resume) (resume 1)))) (scaled 3)) 2)
  (unit))
