(import
 (lofi base))
(def Box (datatype ()
           (box
            (impossible Never))))
(box (unreachable))
