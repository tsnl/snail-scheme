(import
 (snail-core base))
(struct Job
  ((work (Once (-> Unit)))))
(let ((job (Job (once (lambda () (unit)))))) (call-once (Job-work job)))
