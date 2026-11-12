(import
 (snail core base)
 (snail shell task))
(effect Missing ((missing (Fn → Unit))))
(dispatch-local (once (lambda () (missing))))
