(import
 (snail core base))
(struct Job
  ((work (dyn (FnOnce → Unit)))))
(let ((job (Job (once (lambda () (unit)))))) (call-once (● job work)))
