(import
 (snail core base))
(struct Job
  ((work (FnOnce → Unit))))
(let ((job (Job (once (lambda () (unit)))))) (call-once (● job work)))
