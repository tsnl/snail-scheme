(import
 (snail core base)
 (snail core io))

(struct Model
  ((title String)
   (work (FnOnce → Unit))))

(define (main) (→ Unit) (! mut output-port)
  ;; The signature records cleanup of a counted argument alongside its read.
  (let ((read (ann (lambda (model) (● model title)) (Fn (Rc Model) → String ! mut))))
    (let ((model (rc (Model "x" (once (lambda () (unit)))))))
      (write-line (read model))))
  (unit))
