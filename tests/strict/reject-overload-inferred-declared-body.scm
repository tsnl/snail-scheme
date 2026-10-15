(import (snail strict))
(: bridge (-> I64 I64))
(define (bridge value) (i64-add (countdown value) #t))
(define-overload countdown
  (lambda (value) (if (= value 0) 42 (bridge (- value 1)))))
42
