(import
 (snail core base))

(struct Model
  ((title String)
   (work (dyn (FnOnce -> Unit)))))

(: escaped (impl (Fn (Borrow Model) -> (dyn (Fn -> String)))))
(define (escaped model)
  (lambda () (::title model)))
