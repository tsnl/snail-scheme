(define-library (shared model)
  (export
   Model make-model title)
  (import
   (snail core base))
  (begin
    (struct Model
      ((title String)
       (work (FnOnce → Unit))))

    (define (make-model (text String)) (→ (Rc Model))
      (rc (Model text (once (lambda () (unit))))))

    (define (title (model (Rc Model))) (→ String) (! mut)
      (● model title))))
