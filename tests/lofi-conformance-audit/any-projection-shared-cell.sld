(import
 (lofi primitive))
(def cell (ref (ann 1 I64)))
(def hidden Any cell)
(def alias (ann hidden (Ref I64)))
(ref-set! alias (ann 42 I64))
(ref-get cell)
