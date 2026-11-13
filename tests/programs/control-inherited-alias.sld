(import
 (snail core base)
 (snail core io)
 (only (snail core forms) host)
 (only (snail core primitive) inherit-handlers))

(effect Reading ((read-number (Fn → I64))))
(enum Step
  (Done ((value I64)))
  (More ((reader (FnOnce → I64 ! host))
         (next (FnOnce Unit → Step ! Reading)))))
(effect Pause ((ctl pause (Fn (FnOnce → I64 ! host) → Unit))))

(define (start) (→ Step) (! Reading)
  (handle Pause ((pause (lambda (reader resume) (More reader resume))))
    (pause (inherit-handlers (once (lambda () (read-number)))))
    (Done (read-number))))

(define (answer (step Step)) (→ I64) (! Reading host)
  (match step
    ((Done value) value)
    ((More reader next) (drop reader) (drop next) -1)))

(define (main) (→ Unit) (! host output-port)
  (match (handle Reading ((read-number (lambda () 1))) (start))
    ((Done value) (write-line (show value)))
    ((More reader next)
     (write-line (show (handle Reading ((read-number (lambda () 2))) (answer (next (unit))))))
     (write-line (show (reader)))))
  (unit))
