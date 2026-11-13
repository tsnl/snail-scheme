(import
 (snail core base))

(struct Handle
  ((id I64))
  )
(instance (Drop (!) Handle)
  (define (drop (value Handle)) (→ Unit)
    (match value ((Handle _) (unit)))))

(struct Wrapper
  ((handle Handle))
  (deriving Repr))
