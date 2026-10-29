(import
 (snail core base))
(: count (All (T) (-> (List T) I64)))
(define (count items) (length items))
(count (list 1 2))
