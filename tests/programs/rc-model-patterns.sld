(import
 (snail core base)
 (snail core io))

(struct Child
  ((name String))
  (deriving Move))

(struct Model
  ((title String)
   (count I64)
   (pending (Option (Rc Child)))
   (work (FnOnce → Unit))))

;; Matching a copied option preserves the model's copy. The child has an
;; explicit shared owner; its linear payload never leaves the Rc.
(define (describe (model (Rc Model))) (→ String) (! mut)
  (string-append (● model title) " " (show (● model count)) " "
                 (match (● model pending)
                   ((Some child) (● child name))
                   ((None) "none"))))

(define (finish (model (Rc Model))) (→ Unit) (! mut)
  ((replace! (● model work) (once (lambda () (unit))))))

(define (main) (→ Unit) (! mut output-port)
  (let ((model (rc (Model "ready" 2 (Some (rc (Child "nested"))) (once (lambda () (unit)))))))
    (write-line (describe model))
    (write-line (describe model))
    (finish model))
  (let ((model (rc (Model "idle" 0 (None) (once (lambda () (unit)))))))
    (write-line (describe model))
    (finish model))
  (unit))
