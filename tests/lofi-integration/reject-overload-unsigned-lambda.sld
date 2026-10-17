(import (lofi base))
(define-overload identity (lambda (value) value))
(identity (ann 42 I64))
