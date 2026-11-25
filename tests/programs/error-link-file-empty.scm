;; A linked path may climb out with `..` or be absolute, but every name in
;; it is a name: an empty one is a mistake.
(import
 (snail core base)
 (snail shell resource))

(define (image) (→ Resource) (link-file "data//pixel.png"))
