(import
 (snail-core base)
 (snail-core io))

;; An ordinary effect is lost the same way: through Any, a function that
;; logs would come back total, and run where nothing handles Log.
(effect Log
  ((log (-> String Unit))))

(: noisy (-> Unit ! Log))
(define (noisy) (log "hi"))

(: boxed Any)
(define boxed (type-convert noisy Any))

(: quiet (-> Unit))
(define quiet (type-convert boxed (-> Unit)))

(quiet)
