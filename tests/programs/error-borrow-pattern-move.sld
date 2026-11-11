(import
 (snail core base))

(struct Child
  ((name String))
  (deriving Move))

(struct Model
  ((title String)
   (child Child)))

;; A linear field bound by a pattern on a borrow is itself a borrow.
(define (steal (model (Borrow Model))) (→ Unit)
  (match model
    ((Model _ child) (drop child))))
