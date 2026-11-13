(import
 (snail core base))

;; Replacing a linear field would discard what it held.
(struct Job
  ((name String)
   (work (FnOnce → Unit))))

(define (reschedule (job Job)) (→ Job)
  (Job-work-set job (once (lambda () (unit)))))
