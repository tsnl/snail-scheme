(import
 (snail core base))

(: invoke (All (T e) (impl (Fn (Borrow T) (dyn (Fn -> Unit ! e)) -> Unit ! e))))
(define (invoke value callback)
  (callback))
