(import
 (snail core base))

;; A path names a field the record's type does not have.
(struct Point
  ((x I64)
   (y I64)))

(::z (Point 1 2))
