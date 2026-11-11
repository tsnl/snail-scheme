(import
 (snail core base))

(define (invoke (value (Borrow T)) (callback (dyn (Fn → Unit ! e)))) (→ Unit) (! e) (∀ T e)
  (callback))
