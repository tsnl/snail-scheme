(import
 (lofi primitive))
(define-syntax bind-syntax (syntax-rules () ((_ name rules) (define-syntax name rules))))
(make-def answer (lambda () 42))
(bind-syntax make-def (syntax-rules () ((_ name value) (def name value))))
(answer)
