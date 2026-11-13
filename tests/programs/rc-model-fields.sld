(import
 (snail core base)
 (snail core io))

(struct Child
  ((name String))
  (deriving Move))

(struct Model
  ((title String)
   (child (Rc Child))))

(define (child-name (child (Rc Child))) (→ String) (! mut)
  (● child name))

(define (copy-value (value (Rc T))) (→ T) (! mut e) (∀ T e) (⊨ (Copy T) (Drop e T))
  (rc-get value))

(define (main) (→ Unit) (! mut output-port)
  (let ((model (Model "ready" (rc (Child "nested")))) (other (Child "consumed")))
    (let ((child (● model child)))
      (write-line (child-name child))
      (write-line (child-name child)))
    (write-line (● model title))
    (drop other)
    (write-line (child-name (● model child))))
  (write-line (show (copy-value (rc 42))))
  (unit))
