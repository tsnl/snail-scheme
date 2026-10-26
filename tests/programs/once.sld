(import
 (lofi base)
 (lofi io)
 (owned work))

(struct Job
  ((work (Once (-> Unit ! console)))))
(enum Bundle
  (Full ((job Job) (tag I64)))
  (Empty))
(enum Chain
  (Link ((work (Once (-> Unit ! console))) (rest Chain)))
  (End))

(effect Probe ((ping (-> Unit))))

(: drain (-> Chain Unit ! console))
(define (drain chain)
  (match chain
    ((Link work rest) (call-once work) (drain rest))
    ((End) (unit))))

;; Specializing an unrestricted parameter may retain a procedure whose
;; result is affine. Calling that procedure still produces one owned value.
(: preserve (All (A) (-> A A)))
(define (preserve value) value)

(let ((work (message "moved"))) (run work))
(let ((work (message "branch"))) (if #t (call-once work) (call-once work)))
(let* ((inner (message "capture")) (outer (once (lambda () (call-once inner)))))
  (call-once outer))
(let ((unused (message "must not run"))) (write-line "dropped"))
(match (Full (Job (message "matched")) 2)
  ((Full (Job work) 1) (call-once work))
  ((Full (Job work) _) (call-once work))
  ((Empty) (unit)))
(match (Full (Job (message "must not run")) 2)
  ((Full (Job work) 1) (call-once work))
  (_ (write-line "wildcard")))
(drain (Link (message "first") (Link (message "last") (End))))
(let ((unused (Job (handle Probe ((ping (lambda () (unit)))) (message "must not run")))))
  (write-line "handled drop"))
(call-once ((preserve message) "specialized"))
