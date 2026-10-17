(import
 (lofi primitive))

;; A sequential alias cannot generalize variables in the parameter's type.
((lambda (function)
   (begin
     (let alias function)
     (alias (ann 42 I64))
     (alias #t)))
 (lambda (value) value))
