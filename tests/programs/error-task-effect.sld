(import
 (snail core base)
 (snail shell task))
(effect Missing ((missing (dyn (Fn -> Unit)))))
(dispatch-local (once (lambda () (missing))))
