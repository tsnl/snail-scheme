(import
 (lofi base))

(def apply (-> (All (T) (-> T T)) I64)
     (lambda (function) (function 42)))
42
