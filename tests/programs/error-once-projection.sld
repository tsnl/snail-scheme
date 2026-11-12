(import
 (snail core base))

(struct Job
  ((work (FnOnce → Unit))))

(define main
  (lambda ()
    (let ((job (Job (once (lambda () (unit)))))) (call-once (● job work)))
    (unit)))
