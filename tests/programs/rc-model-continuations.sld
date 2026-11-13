(import
 (snail core base)
 (snail core io)
 (snail shell task))

(struct Model
  ((title String))
  )
(instance (Drop (!) Model)
  (define (drop (value Model)) (→ Unit)
    (match value ((Model _) (unit)))))

;; A suspended closure owns a counted copy of its model. Dropping the
;; caller's copy before it runs cannot invalidate that capture.
(define (work (model (Rc Model))) (→ (FnOnce → Unit ! mut tasks output-port))
  (once (lambda ()
          (yield)
          (write-line (● model title)))))

(define (main) (→ Unit) (! mut output-port tasks)

  (let* ((model (rc (Model "after the owner")))
         (task (work model)))
    (drop model)
    (task))
  (unit))
