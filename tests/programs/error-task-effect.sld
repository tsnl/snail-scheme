(import
 (snail-core base)
 (snail-core task))
(effect Missing ((missing (-> Unit))))
(dispatch-local (once (lambda () (missing))))
