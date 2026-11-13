(import
 (snail core base)
 (snail core io))

(struct Model
  ((count I64)
   (work (FnOnce → Unit))))

(define (bump (model (Rc Model))) (→ Unit) (! mut)
  (set! (● model count) (+ 1 (● model count))))

(define (main) (→ Unit) (! mut output-port)
  (let ((model (rc (Model 0 (once (lambda () (unit)))))))
    (bump model)
    (bump model)
    ((replace! (● model work) (once (lambda () (unit)))))
    (write-line (show (● model count))))
  (unit))
