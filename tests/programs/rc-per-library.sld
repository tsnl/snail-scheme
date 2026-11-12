(import
 (snail core base)
 (snail core io)
 (shared model))

(define (inspect (model (Rc Model))) (→ String) (! mut)
  (title model))

(define (main) (→ Unit) (! mut output-port)
  (let ((model (make-model "across libraries")))
    (write-line (inspect model))
    (write-line (title model)))
  (unit))
