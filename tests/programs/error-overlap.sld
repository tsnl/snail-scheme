(import
 (snail core base))

(instance (Repr (List I64))
  (define (repr (items (List I64))) (→ String)
    "numbers"))
