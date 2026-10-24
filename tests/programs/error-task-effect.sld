(import
 (lofi base)
 (lofi task))
(effect Missing ((missing (-> Unit))))
(dispatch-local (once (lambda () (missing))))
