(import (rename (snail strict) (define-overload overload)))
(define-syntax declare
  (syntax-rules ()
    ((_ name) (begin (overload name (-> I64 I64) (lambda (value) value))
                     (overload name (-> Bool I64) (lambda (value) (if value 42 0)))))))
(declare select)
(select #t)
