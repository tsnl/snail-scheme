(def bad (syntax-rules () ((_ (x ...) (y ...)) #((x y) ...))))
(bad (1 2) (3))
