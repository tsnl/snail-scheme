(import
 (snail core base)
 (snail core io))

;; An ordinary effect is lost the same way: through Any, a function that
;; logs would come back total, and run where nothing handles Log.
(effect Log
  ((log (Fn String → Unit))))

(define (noisy) (→ Unit) (! Log) (log "hi"))

(define boxed (→ Any) (Any noisy))

(define quiet
  (→ (Fn → Unit))
  (match (downcast (Fn → Unit) boxed) ((Some value) value) ((None) (panic "type mismatch"))))

(define main
  (lambda ()
    (quiet)
    (unit)))
