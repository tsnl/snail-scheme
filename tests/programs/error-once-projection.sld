(import
 (snail core base))

(record Job
  ((work (FnOnce → Unit))))

(define main
  (lambda ()
    (let ((job (new Job (work (once (lambda () (unit))))))) (call-once (● job work)))
    (unit)))
