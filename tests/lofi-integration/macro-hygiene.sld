(import
 (lofi primitive))
(def helper (lambda (x) (i32-add x 1)))
(define-syntax add (syntax-rules () ((_ value) (begin (let temporary 1) (i32-add temporary (helper value))))))
((lambda ()
   (begin (let temporary 40) (let helper (lambda (x) 999)) (add temporary))))
