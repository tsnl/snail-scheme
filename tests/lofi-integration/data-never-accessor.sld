(import
 (lofi base))
(def Choice (datatype ()
              (live)
              (dead
               (impossible Never dead-value))))
(dead-value (live))
