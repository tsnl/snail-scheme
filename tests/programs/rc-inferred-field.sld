(import
 (snail core base)
 (snail core io))

(record Model
  ((title String)
   (work (FnOnce → Unit))))

(define (main) (→ Unit) (! mut output-port)
  ;; The signature records cleanup of a counted argument alongside its read.
  (let ((read (ann (lambda (model) (● model title)) (Fn (Rc Model) → String ! mut))))
    (let ((model (rc (new Model (title "x") (work (once (lambda () (unit))))))))
      (write-line (read model))))
  (unit))
