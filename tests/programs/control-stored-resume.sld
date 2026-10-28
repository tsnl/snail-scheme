(import
 (snail-core base)
 (snail-core io))

;; `resume` is a value: a handler can return it instead of calling it, and
;; whoever holds it resumes the computation later, after the handler has
;; returned, under whatever handlers are in scope where it is called.
(effect Gen
  ((ctl yield (-> I64 Unit))))

(effect Log
  ((log (-> String Unit))))

;; A step of a generator: done, or a value and the rest, which may be
;; resumed once. Holding `resume` makes a Step affine.
(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (Once (-> Unit Step ! Log))))))

;; The generator's first step: the handler hands back each value with the
;; rest of the body still to run.
(: start (-> (-> Unit ! Gen Log) Step ! Log))
(define (start body)
  (handle Gen ((yield (lambda (value resume) (Yielded value resume))))
    (body)
    (Done)))

(: count-from (-> String I64 I64 Unit ! Gen Log))
(define (count-from name first count)
  (when (> count 0)
    (log (string-append name " produces " (show first)))
    (yield first)
    (count-from name (+ first 1) (- count 1))))

(struct Pair-of-steps
  ((left Step)
   (right Step)))

;; Both generators take their first step under one log.
(: begin-both (-> Pair-of-steps ! console))
(define (begin-both)
  (handle Log ((log (lambda (line)
                      (write-line (string-append "first log: " line)))))
    (Pair-of-steps (start (lambda () (count-from "a" 1 3)))
                   (start (lambda () (count-from "b" 10 2))))))

;; The rest alternates between them, long after their handlers returned,
;; under another log: each resumed step logs to the handler in scope here.
(: alternate (-> Step Step Unit ! Log console))
(define (alternate this other)
  (match this
    ((Done)
     (match other
       ((Done) (write-line "both done"))
       (rest (alternate rest (Done)))))
    ((Yielded value next)
     (write-line (string-append "got " (show value)))
     (alternate other (next (unit))))))

(match (begin-both)
  ((Pair-of-steps left right)
   (handle Log ((log (lambda (line)
                       (write-line (string-append "second log: " line)))))
     (alternate left right))))

;; A control effect in the resumed part: the generator asks for a scale
;; with a control operation, which the handler in scope where it is
;; resumed answers. The node of the generator's handler takes the
;; resumer's evidence as its outside, so the yield reaches that handler,
;; not the one that was in scope when the generator started.
(effect Ask
  ((ctl ask (-> I64))))

(enum Asking
  (Finished)
  (Gave
   ((value I64)
    (next (Once (-> Unit Asking ! Ask))))))

(: scaled (-> I64 Asking ! Ask))
(define (scaled count)
  (handle Gen ((yield (lambda (value resume) (Gave value resume))))
    (let loop ((index 1))
      (when (<= index count)
        (yield (* index (ask)))
        (loop (+ index 1))))
    (Finished)))

(: drain (-> Asking I64 Unit ! console))
(define (drain step scale)
  (match step
    ((Finished) (write-line "finished"))
    ((Gave value next)
     (write-line (string-append "gave " (show value)))
     (drain (handle Ask ((ask (lambda (resume) (resume scale)))) (next (unit)))
            (* scale 10)))))

(drain (handle Ask ((ask (lambda (resume) (resume 1)))) (scaled 3)) 2)
