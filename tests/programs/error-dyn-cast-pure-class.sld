(import
 (snail core base))

(instance (Num (! dyn-cast) Any) (dispatch I64))

(define (pure-sum (a T) (b T)) (→ T) (∀ T) (⊨ (Num (!) T)) (+ a b))

(define main
  (lambda ()
    (handle dyn-cast ((conversion-failed (lambda (_) (unit))))
      (pure-sum (ann 1 Any) (ann 2 Any))
      (unit))
    (unit)))
