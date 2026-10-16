(import (lofi primitive))

;; Immediate application cannot generalize the receiving parameter.
((lambda (function)
   (begin (function (ann 42 I64)) (function #t)))
 (lambda (value) value))
