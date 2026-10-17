(import
 (lofi base))
(def Has (typeclass ( T) (: get (-> T))))
(def lofi-migration-instance-1 (instance (Has I64) (get (lambda () (ann 42 I64)))))
(define-overload choose (All (T) (=> ((Has T)) (-> T T)))
  (lambda (ignored) (get)))
(define-overload choose (-> Bool Bool) (lambda (value) value))
(choose #t)
