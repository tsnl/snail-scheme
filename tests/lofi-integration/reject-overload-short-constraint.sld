(import
 (lofi base))

(def add (All (A B) (requires (+ A A)) (-> A B))
     (lambda (value) (+ value value)))
0
