(import
 (lofi base))
(def Growing (datatype ( T)
               (end)
               (more
                (child (Growing (List T))))))
(ann (end) (Growing I64))
