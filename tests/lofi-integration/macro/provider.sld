(define-library (macro provider)
  (import (lofi primitive))
  (export add-one recognize marker)
  (begin
    (def helper (lambda (x) (i32-add x 1)))
    (def marker 7)
    (def private-step (syntax-rules () ((_ value) (helper value))))
    (def add-one (syntax-rules () ((_ value) (private-step value))))
    (def recognize (syntax-rules (marker) ((_ marker) 40) ((_ value) 2)))))
