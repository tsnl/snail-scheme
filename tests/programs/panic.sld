(import
 (snail-core base)
 (snail-core io))

(: head (All (T) (-> (List T) T)))
(define (head items)
  (match items
    ((Cons item _) item)
    ((Nil) (panic "head of an empty list"))))

(write-line "start")
(display (head (ann (Nil) (List I64))))
