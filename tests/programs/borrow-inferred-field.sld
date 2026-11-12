(import
 (snail core base)
 (snail core io))

(struct Model
  ((title String)
   (work (FnOnce → Unit))))

;; The receiver becomes a Borrow after this lambda has been inferred.
(let ((read (lambda (r) (● r title))))
  (let ((model (Model "x" (once (lambda () (unit))))))
    (write-line (with-borrow (b model) (read b)))
    (drop model)))
