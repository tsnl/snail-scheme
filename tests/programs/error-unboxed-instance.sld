(import
 (snail core base))

;; Unboxed follows from a type's representation; a program cannot declare it.
(struct Point
  ((x I64)
   (y I64)))

(instance (Unboxed Point))
