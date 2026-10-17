(import
 (lofi primitive))
(def boxed (All (T) Any)
     (ann (ann (lambda (value) value) (-> T T)) Any))
(def number-identity (ann (inst boxed I64) (-> I64 I64)))
(def bool-identity (ann (inst boxed Bool) (-> Bool Bool)))
(if (bool-identity #t) (number-identity (ann 42 I64)) (ann 0 I64))
