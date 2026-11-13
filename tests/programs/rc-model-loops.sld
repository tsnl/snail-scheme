(import
 (snail core base)
 (snail core io))

(struct Model
  ((title String)
   (work (FnOnce → Unit))))

(define (count-to (model (Rc Model)) (limit I64)) (→ I64) (! mut)
  (let loop ((n 0) (current model))
    (if (< n limit) (loop (+ n 1) current)
        (string-length (● (ann current (Rc Model)) title)))))

(define (read (model (Rc Model))) (→ String) (! mut)
  (● model title))

(define (main) (→ Unit) (! mut output-port)
  (let ((model (rc (Model "abcd" (once (lambda () (unit)))))))
    (write-line (show (count-to model 3)))
    (write-line (read model)))
  (unit))
