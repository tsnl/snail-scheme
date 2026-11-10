(import
 (snail core base))

(: use (impl (Fn (dyn (FnOnce -> Unit)) -> Unit)))
(define (use work)
  (call-once work))

(expose use "use")
