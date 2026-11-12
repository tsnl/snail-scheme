(define-library (borrow model)
  (export
   Model make-model title)
  (import
   (snail core base))
  (begin
    (struct Model
      ((title String)
       (work (FnOnce → Unit))))

    (define (make-model (text String)) (→ Model)
      (Model text (once (lambda () (unit)))))

    (define (title (model (Borrow Model))) (→ String)
      (● model title))))
