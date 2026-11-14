(import
 (snail core base)
 (snail core io)
 (only (snail core forms) host)
 (only (snail core primitive) inherit-handlers-1))

(effect Reading ((read-number (Fn → I64))))
(record Resource
  ((value I64)))
(instance (Drop (! Reading output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! Reading output-port)
    (match resource
      ((Resource value) (write-line (show (+ value (read-number))))))))

(enum Step
  (Done)
  (More ((discard (FnOnce (FnOnce Unit → Step ! output-port) → Unit ! host))
         (next (FnOnce Unit → Step ! output-port)))))
(effect Pause
  ((ctl pause (Fn (FnOnce (FnOnce Unit → Step ! output-port) → Unit ! host) → Unit))))

(define (start) (→ Step) (! output-port)
  (handle Pause ((pause (lambda (discard resume) (More discard resume))))
    (handle Reading ((read-number (lambda () 7)))
      (let ((resource (new Resource (value 10))))
        (pause (inherit-handlers-1 (once (lambda (next) (drop next)))))
        (drop resource)
        (Done)))))

(define (main) (→ Unit) (! host output-port)
  (match (start)
    ((Done) (unit))
    ((More discard next) (discard next))))
