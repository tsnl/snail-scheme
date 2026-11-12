(import
 (snail core base)
 (snail core io))

;; An ordinary effect is lost the same way: through Any, a function that
;; logs would come back total, and run where nothing handles Log.
(effect Log
  ((log (Fn String → Unit))))

(define (noisy) (→ Unit) (! Log) (log "hi"))

(define boxed (→ Any) (type-convert noisy Any))

(define quiet (→ (Fn → Unit)) (type-convert boxed (Fn → Unit)))

(define main
  (lambda ()
    (quiet)
    (unit)))
