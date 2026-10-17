(import
 (lofi base)
 (lofi io))
(def port
     (open-input-file "λ😀.txt"))
(read-line port)
(unreachable)
