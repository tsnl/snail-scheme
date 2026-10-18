(import
 (lofi base))

(def bad (All (T) (requires) (-> T T))
     (lambda (value) (begin (ann (default) T) value)))
(bad 42)
