(import
 (snail core base)
 (snail core io))

;; An ordinary effect is lost the same way: through Any, a function that
;; logs would come back total, and run where nothing handles Log.
(effect Log
  ((log (dyn (Fn String → Unit)))))

(define (noisy) (→ Unit) (! Log) (log "hi"))

(define boxed (→ Any) (type-convert noisy Any))

(define quiet (→ (dyn (Fn → Unit))) (type-convert boxed (dyn (Fn → Unit))))

(quiet)
