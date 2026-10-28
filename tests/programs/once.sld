(import
 (snail core base)
 (snail core io)
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

(effect Abort ((ctl abort (-> String Never))))

(: drain (-> Chain Unit ! console))
(define (drain chain)
  (match chain
    ((Link work rest) (call-once work) (drain rest))
    ((End) (unit))))

;; Specializing an unrestricted parameter may retain a procedure whose
;; result is linear. Calling that procedure still produces one owned value.
(: preserve (All (A) (-> A A)))
(define (preserve value) value)

(let ((work (message "moved"))) (run work))
(let ((work (message "branch"))) (if #t (call-once work) (call-once work)))
;; A path that cannot return need not consume what it holds: one that
;; panics, or reaches a value of type Never, as an abortive operation
;; answers. What it held is abandoned.
(let ((work (message "diverging branch"))) (if #f (panic "unreachable") (call-once work)))
(handle Abort ((abort (lambda (reason) (write-line reason))))
  (let ((work (message "must not run")))
    (absurd (abort "aborted"))))
(let* ((inner (message "capture")) (outer (once (lambda () (call-once inner)))))
  (call-once outer))
(let ((unused (message "must not run")))
  (drop unused)
  (write-line "dropped"))
(match (Full (Job (message "matched")) 2)
  ((Full (Job work) 1) (call-once work))
  ((Full (Job work) _) (call-once work))
  ((Empty) (unit)))
(match (Full (Job (message "must not run")) 2)
  ((Full (Job work) 1) (call-once work))
  ((Full (Job work) _)
   (drop work)
   (write-line "wildcard"))
  ((Empty) (unit)))
(drain (Link (message "first") (Link (message "last") (End))))
(let ((unused (Job (handle Probe ((ping (lambda () (unit)))) (message "must not run")))))
  (match unused
    ((Job work) (drop work)))
  (write-line "handled drop"))
(call-once ((preserve message) "specialized"))
