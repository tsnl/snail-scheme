(import
 (lofi base))

(def identity (All (T) (=> () (-> T T))) (lambda (value) value))
(identity 42)
