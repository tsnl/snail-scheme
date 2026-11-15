(import
 (snail core base)
 (snail core io)
 (only (snail core forms) host)
 (only (snail core primitive) inherit-handlers))

(effect Reading ((read-number (Fn → I64))))
(enum Step
  (Done ((value I64)))
  (More ((reader (Fn → I64 ! host))
         (next (Fn Unit → Step ! Reading)))))
(effect Pause ((ctl pause (Fn (Fn → I64 ! host) → Unit))))

(define (start) (→ Step) (! Reading)
  (handle Pause ((pause (lambda (reader resume) (More reader resume))))
    (pause (inherit-handlers (lambda () (read-number))))
    (Done (read-number))))

(define (answer (step Step)) (→ I64)
  (match step
    ((Done value) value)
    ((More reader next) -1)))

(define (main) (→ Unit) (! host output-port)
  (match (handle Reading ((read-number (lambda () 1))) (start))
    ((Done value) (write-line (show value)))
    ((More reader next)
     (write-line (show (handle Reading ((read-number (lambda () 2))) (answer (next (unit))))))
     (write-line (show (reader)))))
  (unit))
