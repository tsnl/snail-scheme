(import
 (snail core base))

;; The old inline-layout constraint is no longer a typeclass.
(record Point
  ((x I64)
   (y I64)))

(instance (Unboxed Point))
