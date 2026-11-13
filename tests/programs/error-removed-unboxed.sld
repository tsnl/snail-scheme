(import
 (snail core base))

;; The old inline-layout constraint is no longer a typeclass.
(struct Point
  ((x I64)
   (y I64)))

(instance (Unboxed Point))
