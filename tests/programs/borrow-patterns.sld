(import
 (snail core base)
 (snail core io))

(struct Child
  ((name String))
  (deriving Move))

(struct Model
  ((title String)
   (count I64)
   (pending (Option Child))
   (work (FnOnce → Unit))))

;; A constructor pattern on a borrow binds a Copy field as an owned value
;; and a linear field as a borrow; a wildcard skips a linear field without
;; consuming anything.
(define (describe (model (Borrow Model))) (→ String)
  (match model
    ((Model title count pending _)
     (string-append title " " (show count) " " (pending-name pending)))))

;; An enum is matched through its borrow the same way.
(define (pending-name (pending (Borrow (Option Child)))) (→ String)
  (match pending
    ((Some child) (child-name child))
    ((None) "none")))

(define (child-name (child (Borrow Child))) (→ String)
  (match child
    ((Child name) name)))

(define main
  (lambda ()
    (let ((model (Model "ready" 2 (Some (Child "nested")) (once (lambda () (unit))))))
      (write-line (with-borrow (read model) (describe read)))
      (write-line (with-borrow (read model) (describe read)))
      (match model
        ((Model _ _ pending work)
         (work)
         (drop pending))))
    (let ((model (Model "idle" 0 (None) (once (lambda () (unit))))))
      (write-line (with-borrow (read model) (describe read)))
      (match model
        ((Model _ _ pending work)
         (work)
         (drop pending))))
    (unit)))
