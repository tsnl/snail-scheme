(define-library (macro conflict)
  (export add-one)
  (begin (define-syntax add-one (syntax-rules () ((_) 42)))))
