(import
 (snail core base)
 (snail core io))

;; An ordinary effect is lost the same way: through Any, a function that
;; logs would come back total, and run where nothing handles Log.
(effect Log
  ((log (dyn (Fn String -> Unit)))))

(: noisy (impl (Fn -> Unit ! Log)))
(define (noisy) (log "hi"))

(: boxed Any)
(define boxed (type-convert noisy Any))

(: quiet (dyn (Fn -> Unit)))
(define quiet (type-convert boxed (dyn (Fn -> Unit))))

(quiet)
