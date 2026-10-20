(import
 (lofi core))
(define-syntax include (syntax-rules () ((_) (import
                                    (missing dependency)))))
(include)
42
