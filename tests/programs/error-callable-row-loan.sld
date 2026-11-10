(import
 (snail core base))

(: invoke
   (All (F e)
        (requires (Fn F -> Unit ! e) (Drop e F))
        (impl (Fn F -> Unit ! e))))
(define (invoke function)
  (function)
  (drop function))
