(import
 (snail core base))
(effect Ask ((ask (Fn → I64))))
(define boxed (→ Any) 1)
(handle dyn-cast ((conversion-failed (lambda (_) 0)))
  (handle Ask ((ask (lambda () boxed))) (ask)))
