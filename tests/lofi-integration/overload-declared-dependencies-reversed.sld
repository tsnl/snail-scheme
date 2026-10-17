(import
 (lofi base))
(define-overload f (All (T) (-> T T)) (lambda (value) value))
(def forward
     (lambda (value) (f value)))
(def helper
     forward)
(def bridge
     (lambda (value) (helper value)))
(define-overload g (-> I64 Bool) (lambda (value) #t))
(define-overload g (All (T) (-> T T)) (lambda (value) (bridge value)))
(if (if (ann (g (ann 42 I64)) Bool) (= (ann (g (ann 42 I64)) I64) (ann 42 I64)) #f) (ann 42 I64) (unreachable))
