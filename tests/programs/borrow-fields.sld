(import
 (snail core base)
 (snail core io))

(struct Child
  ((name String))
  (deriving Move))
(struct Model
  ((title String)
   (child Child)))

(define (child-name (child (Borrow Child))) (→ String)
  (::name child))

;; A copied field owns its data. A linear field remains a scoped borrow,
;; including when its projection is bound to a local alias.
(let ((model (Model "ready" (Child "nested"))) (other (Child "consumed")))
  (with-borrow (read model)
               (let ((child (::child read)))
                 (write-line (child-name child))
                 (write-line (child-name child)))
               (with-borrow (also model) (write-line (::title also)))
               (drop other))
  (with-borrow (child (::child model))
               (write-line (child-name child)))
  (drop model))

;; A Copy target can leave the region as an ordinary value.
(define (copy-value (borrowed (Borrow T))) (→ T) (∀ T) (⊨ (Copy T))
  (borrow-copy borrowed))

(let ((number 42))
  (write-line (show (with-borrow (borrowed number) (copy-value borrowed)))))
