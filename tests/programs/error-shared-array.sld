(import
 (lofi base)
 (only (lofi primitive) share-value))

(share-value (make-array 1 (ann 1 I64)))
