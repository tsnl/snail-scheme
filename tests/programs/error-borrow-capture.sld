(import
 (snail core base))

(struct Model
  ((title String)
   (work (dyn (FnOnce → Unit)))))

(define (escaped (model (Borrow Model))) (→ (dyn (Fn → String)))
  (lambda () (● model title)))
