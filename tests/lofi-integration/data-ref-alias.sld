(import
 (lofi base))
(def Cell (datatype ( T)
            (cell
             (value (Ref T) cell-ref))))
(def original
     (cell (ref (ann 5 I64))))
(def alias
     original)
(ref-set! (cell-ref alias) (ann 19 I64))
(if (ref-eq? (cell-ref original) (cell-ref alias)) (ref-get (cell-ref original)) (ann 0 I64))
