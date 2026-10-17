(import
 (lofi base))
(def cell
     (ref (ann 0 I64)))
(def alias
     (ann (ann cell Any) (Ref I64)))
(ref-set! alias (ann 42 I64))
(if (ref-eq? cell alias) (ref-get cell) (ann 0 I64))
