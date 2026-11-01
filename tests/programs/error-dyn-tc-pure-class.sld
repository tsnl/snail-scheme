(import
 (snail core base))
(instance (Num (! dyn-tc) Any) (dispatch I64))
(: pure-sum (All (T) (requires (Num (!) T)) (-> T T T)))
(define (pure-sum a b) (+ a b))
(handle dyn-tc ((conversion-failed (lambda (_) (unit))))
  (pure-sum (ann 1 Any) (ann 2 Any))
  (unit))
