(import
 (lofi base))
(def Choice (datatype ()
              (live
               (value I64))
              (dead
               (impossible Never))))
(match (live (ann 7 I64)) ((live value) value) ((dead impossible) impossible))
