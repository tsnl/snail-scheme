(import
 (snail core base))

(record Handle
  ((id I64))
  )
(instance (Drop (!) Handle)
  (define (drop (value Handle)) (→ Unit)
    (match value ((Handle _) (unit)))))

(record Wrapper
  ((handle Handle))
  (deriving Repr))
