(import
 (lofi base))
(def Choice (datatype ()
              (yes)
              (no)))
(match (yes) ((yes) 1) ((yes) 2))
