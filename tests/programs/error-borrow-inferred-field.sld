(import
 (snail core base)
 (snail core io))

(struct Model
  ((title String)
   (work (FnOnce Unit))))

;; The lambda's parameter has no type when its body is checked, so the
;; field read is not rewritten for a borrow; annotate the parameter.
(let ((read (lambda (r) (::title r))))
  (let ((model (Model "x" (once (lambda () (unit))))))
    (write-line (with-borrow (b model) (read b)))
    (drop model)))
