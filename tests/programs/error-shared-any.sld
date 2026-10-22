(import
 (lofi base)
 (only (lofi primitive) share-value))

(struct Hidden
  ((value Any)))

(share-value (Hidden (type-convert (ref (ann 1 I64)) Any)))
