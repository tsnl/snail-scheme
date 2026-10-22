(import
 (lofi base)
 (only (lofi primitive) share-value))

(struct Callback
  ((run (-> I64 I64))))

(share-value (Callback (lambda (value) value)))
