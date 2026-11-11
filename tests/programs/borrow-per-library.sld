(import
 (snail core base)
 (snail core io)
 (borrow model))

(: inspect (impl (Fn (Borrow Model) -> String)))
(define (inspect model)
  (title model))

(let ((model (make-model "across libraries")))
  (with-borrow (borrowed model)
               (write-line (inspect borrowed))
               (write-line (title borrowed)))
  (drop model))
