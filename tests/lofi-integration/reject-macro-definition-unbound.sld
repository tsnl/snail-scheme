(import
 (lofi core))
(def m (syntax-rules () ((_) absent)))
((lambda (absent) (m)) 42)
