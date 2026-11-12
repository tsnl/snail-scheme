(import
 (snail core base))

(struct Model
  ((title String)
   (work (FnOnce → Unit))))

(define (escaped (model (Borrow Model))) (→ (Fn → String))
  (lambda () (● model title)))
