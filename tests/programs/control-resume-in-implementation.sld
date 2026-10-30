(import
 (snail core base)
 (snail core io))

;; A stored `resume` called inside another handler's implementation runs
;; under that implementation's handlers: those outside its handle, not
;; those where its operation was performed (#565). The generator's handler,
;; re-installed by the resume, runs its own implementation outside itself
;; there too, so both the body and the implementation log to the handler
;; outside the runner.
(effect Gen
  ((ctl yield (-> I64 Unit))))

(effect Log
  ((log (-> String Unit))))

(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (FnOnce Unit Step ! Log)))))

;; The generator hands back each value, and its implementation logs.
(: start (-> (-> Unit ! Gen Log) Step ! Log))
(define (start body)
  (handle Gen ((yield (lambda (value resume)
                        (log (string-append "the handler yields " (show value)))
                        (Yielded value resume))))
    (body)
    (Done)))

(: count-from (-> I64 I64 Unit ! Gen Log))
(define (count-from first count)
  (when (> count 0)
    (log (string-append "the body produces " (show first)))
    (yield first)
    (count-from (+ first 1) (- count 1))))

;; An operation that takes the rest of a generator, which its implementation
;; runs.
(effect Runner
  ((run-step (-> (FnOnce Unit Step ! Log) Step))))

(: show-step (-> Step Unit ! console))
(define (show-step step)
  (match step
    ((Done) (write-line "done"))
    ((Yielded value next)
     (write-line (string-append "got " (show value)))
     (show-step (handle Log ((log (lambda (line) (write-line (string-append "finishing: " line)))))
                  (next (unit)))))))

;; The first step under one log, the second inside the runner's
;; implementation, and the rest under another.
(let ((first (handle Log ((log (lambda (line) (write-line (string-append "start: " line)))))
               (start (lambda () (count-from 1 3))))))
  (match first
    ((Yielded value next)
     (write-line (string-append "got " (show value)))
     (show-step
      (handle Log ((log (lambda (line) (write-line (string-append "outside the runner: " line)))))
        (handle Runner ((run-step (lambda (rest) (rest (unit)))))
          (handle Log ((log (lambda (line)
                              (write-line (string-append "where run-step is performed: " line)))))
            (run-step next))))))
    ((Done) (write-line "done"))))
