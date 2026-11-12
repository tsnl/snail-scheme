(import
 (snail core base))

(define (invoke (value (Borrow T)) (callback (Fn → Unit ! e))) (→ Unit) (! e) (∀ T e)
  (callback))
