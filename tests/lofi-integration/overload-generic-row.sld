(import
 (lofi base))
(define-overload choose (All (T) (-> T T T)) (lambda (left right) left))
(define-overload choose (All (T) (-> T T)) (lambda (value) value))
(def alias
     choose)

(def constrained (All (T) (requires (choose (-> T T T))) (-> T T T))
     (lambda (left right) (choose left right)))
(if (if (choose #t #f) (if (alias #t) (= (constrained (ann 42 I64) (ann 0 I64)) (ann 42 I64)) #f) #f) (ann 42 I64) (unreachable))
