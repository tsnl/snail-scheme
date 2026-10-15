(import (snail strict))
(define-overload keep (All (T) (-> T (-> T)))
  (lambda (value) (lambda () value)))
(if (and ((keep #t)) (= ((keep 42)) 42)) 42 (unreachable))
