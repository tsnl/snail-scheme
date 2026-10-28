(import
 (snail core base)
 (snail shell task))
(effect Missing ((missing (-> Unit))))
(dispatch-local (once (lambda () (missing))))
