(import
 (snail core base))
(effect Ask ((ask (dyn (Fn -> I64)))))
(: boxed Any)
(define boxed 1)
(handle dyn-cast ((conversion-failed (lambda (_) 0)))
  (handle Ask ((ask (lambda () boxed))) (ask)))
