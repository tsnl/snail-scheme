(import
 (lofi base))
(def First (datatype ()
             (first)))
(def Second (datatype ()
              (second)))
(match (first) ((first) 1) ((second) 2))
