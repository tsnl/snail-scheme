(import
 (snail core base))

(: invoke (All (T e) (-> (Borrow T) (-> Unit ! e) Unit ! e)))
(define (invoke value callback)
  (callback))
