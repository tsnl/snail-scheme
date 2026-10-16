(import (lofi base))
;; Ordinary helper inference uses declared family signatures regardless of source order.
(define-overload g (All (T) (-> T T)) (lambda (value) (bridge value)))
(define-overload g (-> I64 Bool) (lambda (value) #t))
(def bridge
     (lambda (value) (helper value)))
(def forward
     (lambda (value) (f value)))
(def helper
     forward)
(define-overload f (All (T) (-> T T)) (lambda (value) value))
(if (if (ann (g (ann 42 I64)) Bool) (= (ann (g (ann 42 I64)) I64) (ann 42 I64)) #f) (ann 42 I64) (unreachable))
