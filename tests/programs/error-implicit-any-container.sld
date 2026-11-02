(import
 (snail core base))

(: integer (-> (Ref I64) I64 ! mut))
(define (integer value) (ref-get value))

(: dynamic (Ref Any))
(define dynamic (ref (ann 1 Any)))
(integer dynamic)
