(import
 (lofi base))
(def Box (datatype ( T)
           (box
            (value T))))
(ann (box 1) Box)
