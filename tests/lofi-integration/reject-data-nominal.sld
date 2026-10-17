(import
 (lofi base))
(def First (datatype ()
             (first
              (value I64 first-value))))
(def Second (datatype ()
              (second
               (value I64 second-value))))
(first-value (second (ann 3 I64)))
