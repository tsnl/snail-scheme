(import
 (snail core base)
 (snail core io))

(struct (annotations T)
  ((value T)))

(struct Wrapped
  ((item (annotations I64) (annotations (doc "An ordinary applied type.")))))

(define item (→ (annotations I64)) (annotations (doc "A value of that type.")) (annotations 9))

(define (main) (→ Unit) (! output-port)
  (write-line (show (● (● (Wrapped item) item) value)))
  (unit))
