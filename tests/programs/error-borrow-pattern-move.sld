(import
 (snail core base))

(struct Child
  ((name String))
  (deriving Move))

(struct Model
  ((title String)
   (child Child)))

;; A linear field bound by a pattern on a borrow is itself a borrow.
(: steal (impl (Fn (Borrow Model) -> Unit)))
(define (steal model)
  (match model
    ((Model _ child) (drop child))))
