((lambda (x y) x) 1 2)
((lambda (x y) y) 1 2)
((lambda (z)
  ((lambda (x y) z) 1 2)) 42)
(call/cc (lambda (ret) (ret 49)))
