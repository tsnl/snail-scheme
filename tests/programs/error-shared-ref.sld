(import
 (lofi base)
 (only (lofi primitive) share-value))

(struct (Envelope T)
  ((values (Vector T))))

(share-value (Envelope (make-vector 1 (ref (ann 1 I64)))))
