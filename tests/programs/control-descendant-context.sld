(import
 (snail core base)
 (snail core io)
 (only (snail core forms) host)
 (only (snail core primitive) inherit-handlers-1))

(effect Reading ((read-number (Fn → I64))))

(enum Step
  (Done ((value I64)))
  (More ((invoke (FnOnce (FnOnce Unit → Step) → Step ! host))
         (next (FnOnce Unit → Step)))))

(effect Pause
  ((ctl pause (Fn (FnOnce (FnOnce Unit → Step) → Step ! host) → Unit))))

(define (start) (→ Step)
  (handle Pause ((pause (lambda (invoke resume) (More invoke resume))))
    (handle Reading ((read-number (lambda () 7)))
      (pause (inherit-handlers-1 (once (lambda (next) (next (unit))))))
      (Done (read-number)))))

(define (show-step (step Step)) (→ Unit) (! host output-port)
  (match step
    ((Done value) (write-line (show value)))
    ((More invoke next) (show-step (invoke next)))))

(define (main) (→ Unit) (! host output-port)
  (show-step (start)))
