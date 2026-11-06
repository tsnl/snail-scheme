(import
 (snail core base))

(struct Model
  ((title String)
   (work (FnOnce Unit))))

(: escaped (-> (Borrow Model) (-> String)))
(define (escaped model)
  (lambda () (::title model)))
