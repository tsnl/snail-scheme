(import
 (snail core base)
 (snail core io))

(define (head (items (List T))) (→ T) (∀ (T))
  (match items
    ((Cons item _) item)
    ((Nil) (panic "head of an empty list"))))

(define (main) (→ Unit) (! output-port)

  (write-line "start")
  (display (head (ann (Nil) (List I64))))
  (unit))
