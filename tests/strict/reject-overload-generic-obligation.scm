(import (snail strict))
(define-overload build (All (T) (-> I64 (Vector T)))
  (lambda (count) (make-vector count)))
42
