(import
 (lofi base))
(def Choice (datatype ()
              (some
               (value I64))
              (none)))
(def f
     (match (some (ann 29 I64)) ((none) (lambda () (ann 0 I64))) ((some value) (lambda () value))))
(f)
