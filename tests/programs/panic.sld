(import
 (snail core base)
 (snail core io))

(define (head (items (List T))) (→ T) (∀ T) (⊨ (Copy T))
  (match items
    ((Cons item _) item)
    ((Nil) (panic "head of an empty list"))))

(write-line "start")
(display (head (ann (Nil) (List I64))))
