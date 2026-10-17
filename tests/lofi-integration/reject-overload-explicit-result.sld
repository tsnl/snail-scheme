(import
 (lofi base))
(def bad
     (inst + (-> I64 I64 F64)))
(bad 20 22)
