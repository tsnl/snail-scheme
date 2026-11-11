(import
 (snail core base)
 (snail core io))

;; An operation's default may be a Snail-Core function, which runs when no
;; handler of its effect is in scope, under the handlers in scope where the
;; operation is performed: here `sleep-until` waits on its caller's
;; scheduler, and `now` is pure.
;; ANCHOR: clock
(effect Async
  ((ctl await (dyn (Fn I64 -> I64)))))

(effect Clock
  ((now (dyn (Fn -> I64)))
   (sleep-until (dyn (Fn I64 -> I64 ! Async))))
  (default
    ((now (lambda () 1000))
     (sleep-until wait-for))))

(: wait-for (impl (Fn I64 -> I64 ! Async)))
(define (wait-for deadline)
  (await deadline))
;; ANCHOR_END: clock

(enum Task
  (Done
   ((value I64)))
  (Waiting
   ((deadline I64)
    (next (dyn (FnOnce I64 -> Task ! Clock console))))))

(: start (impl (Fn (dyn (Fn -> I64 ! Clock Async console)) -> Task ! Clock console)))
(define (start body)
  (handle Async ((await (lambda (deadline resume) (Waiting deadline resume))))
    (Done (body))))

(: job (impl (Fn -> I64 ! Clock Async console)))
(define (job)
  (let ((woke (sleep-until (+ (now) 5))))
    (write-line (string-append "woke at " (show woke)))
    (sleep-until (+ woke 1))))

;; Wakes each sleeper at its deadline, after its handler has returned.
(: drive (impl (Fn Task -> Unit ! Clock console)))
(define (drive task)
  (match task
    ((Done value) (write-line (string-append "done at " (show value))))
    ((Waiting deadline next)
     (write-line (string-append "waiting until " (show deadline)))
     (drive (next deadline)))))

(drive (start job))

;; A handler replaces the defaults: this clock never waits.
(drive (handle Clock
           ((now (lambda () 0))
            (sleep-until (lambda (deadline) (+ deadline 100))))
         (start job)))
