(import
 (snail core base))

;; Replacing a linear field would discard what it held.
(struct Job
  ((name String)
   (work (dyn (FnOnce -> Unit)))))

(: reschedule (impl (Fn Job -> Job)))
(define (reschedule job)
  (Job-work-set job (once (lambda () (unit)))))
