(import
 (lofi base))

(def bad (All (T) (requires (Default T)) (-> T T))
     (lambda (value) 42))
(bad 42)
