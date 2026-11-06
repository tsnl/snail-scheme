(import
 (snail core base))

(: stolen (All (T) (-> (Borrow T) T)))
(define (stolen value)
  value)
