(import
 (lofi base))
(def Identity (typeclass ( T) (: identity (-> T T))))
(define-overload invalid (All (T) (requires (Identity T)) (-> T T)) identity)
(ann 42 I64)
