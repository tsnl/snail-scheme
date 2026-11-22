(import
 (snail core base)
 (snail core io))

(define (head (items (List T))) (→ T) (∀ (T))
  (match items
    ((Cons item _) item)
    ((Nil) (panic "head of an empty list"))))

(define (main (out OutputPort)) (→ Unit) (! mut)

  (write-line out "start")
  (display out (head (ann (Nil) (List I64))))
  (unit))
