(import
 (snail core base))
(: consuming
   (All (F e)
        (requires (FnOnce F -> Unit ! e))
        (impl (Fn F -> Unit ! e))))
(define (consuming function) (function))
(: shared
   (All (F e)
        (requires (Fn F -> Unit ! e))
        (impl (Fn F -> Unit ! e))))
(define (shared function) (consuming function))
