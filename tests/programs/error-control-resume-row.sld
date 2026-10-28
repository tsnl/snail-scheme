(import
 (snail core base)
 (snail core io))

;; The handler is deep and resuming rebases it, so each later yield runs
;; the implementation under the handlers where `resume` was called. Its
;; `log` then needs a Log handler there, so `resume` performs the handle's
;; context row, Log here, and a Step that stores it must say so.
(effect Gen
  ((ctl yield (-> I64 I64))))

(effect Log
  ((log (-> String Unit))))

;; ANCHOR: step
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
;; ANCHOR_END: step

(: counter (-> Unit ! Gen))
(define (counter)
  (yield 1)
  (yield 2)
  (unit))

;; With no Log handler around `next`, the second yield would log to none.
(match (handle Log ((log (lambda (line) (write-line line)))) (start counter))
  ((Yielded value next)
   (write-line (string-append "got " (show value)))
   (match (next 10)
     ((Yielded value _) (write-line (string-append "got " (show value))))
     ((Done) (write-line "done"))))
  ((Done) (write-line "done at once")))
