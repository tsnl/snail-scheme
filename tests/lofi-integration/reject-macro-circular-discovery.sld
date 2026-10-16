(def bind (syntax-rules () ((_ name value) (def name value))))
(begin (bind bind (lambda (x y) x)) 0)
