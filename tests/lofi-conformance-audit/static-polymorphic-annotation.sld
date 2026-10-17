(import
 (lofi primitive))
(def identity (All (T) (-> T T))
     (ann (lambda (value) value) (-> T T)))
(def alias (All (T) (-> T T)) (ann identity (-> T T)))
(def number-identity (ann (inst alias I64) (-> I64 I64)))
(if (alias #t) (number-identity (ann 42 I64)) (ann 0 I64))
