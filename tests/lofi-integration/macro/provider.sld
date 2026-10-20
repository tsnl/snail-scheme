(define-library (macro provider)
  (import
   (lofi primitive))
  (export add-one recognize marker)
  (begin
    (def helper (lambda (x) (i32-add x 1)))
    (def marker 7)
    (define-syntax private-step (syntax-rules () ((_ value) (helper value))))
    (define-syntax add-one (syntax-rules () ((_ value) (private-step value))))
    (define-syntax recognize (syntax-rules (marker) ((_ marker) 40) ((_ value) 2)))))
