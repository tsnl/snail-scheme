(import
 (lofi core)
 (lofi base))

(def value 40)
(def inner (begin (def value 2) value))
(+ value inner)
