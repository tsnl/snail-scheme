(import
 (snail core base)
 (snail core io))

;; A struct's field is read by path; its accessor name is reserved, so a
;; read through it is refused and a definition of it is a duplicate.
(struct Point
  ((x I64)))

(write-line (show (Point-x (Point 1))))
