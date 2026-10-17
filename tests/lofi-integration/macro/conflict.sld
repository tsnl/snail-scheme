(define-library (macro conflict)
  (export add-one)
  (begin (def add-one (syntax-rules () ((_) 42)))))
