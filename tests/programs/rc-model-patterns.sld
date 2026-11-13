(import
 (snail core base)
 (snail core io))

(record Child
  ((name String))
  )
(instance (Drop (!) Child)
  (define (drop (value Child)) (→ Unit)
    (match value ((Child _) (unit)))))

(record Model
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
  (let ((model (rc (new Model
                     (title "ready")
                     (count 2)
                     (pending (Some (rc (new Child (name "nested")))))
                     (work (once (lambda () (unit))))))))
    (write-line (describe model))
    (write-line (describe model))
    (finish model))
  (let ((model (rc (new Model
                     (title "idle")
                     (count 0)
                     (pending (None))
                     (work (once (lambda () (unit))))))))
    (write-line (describe model))
    (finish model))
  (unit))
