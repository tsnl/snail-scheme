(define-library (borrow model)
  (export
   Model make-model title)
  (import
   (snail core base))
  (begin
    (struct Model
      ((title String)
       (work (dyn (FnOnce -> Unit)))))

    (: make-model (impl (Fn String -> Model)))
    (define (make-model text)
      (Model text (once (lambda () (unit)))))

    (: title (impl (Fn (Borrow Model) -> String)))
    (define (title model)
      (::title model))))
