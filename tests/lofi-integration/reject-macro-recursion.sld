(def forever (syntax-rules () ((_ x) (forever x))))
(forever 1)
