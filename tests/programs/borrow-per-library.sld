(import
 (snail core base)
 (snail core io)
 (borrow model))

(define (inspect (model (Borrow Model))) (→ String)
  (title model))

(define main
  (lambda ()
    (let ((model (make-model "across libraries")))
      (with-borrow (borrowed model)
                   (write-line (inspect borrowed))
                   (write-line (title borrowed)))
      (drop model))
    (unit)))
