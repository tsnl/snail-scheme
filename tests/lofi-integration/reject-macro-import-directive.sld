(import
 (lofi core))
(def include (syntax-rules () ((_) (import
                                    (missing dependency)))))
(include)
42
