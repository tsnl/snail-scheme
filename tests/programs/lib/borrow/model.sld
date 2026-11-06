(define-library (borrow model)
  (export
   Model make-model title)
  (import
   (snail core base))
  (begin
    (struct Model
      ((title String)
       (work (FnOnce Unit))))

    (: make-model (-> String Model))
    (define (make-model text)
      (Model text (once (lambda () (unit)))))

    (: title (-> (Borrow Model) String))
    (define (title model)
      (::title model))))
