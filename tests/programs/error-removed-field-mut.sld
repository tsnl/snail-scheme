(import
 (snail core base))

;; All fields are mutable; the old per-field annotation is gone.
(struct Counter
  ((count mut I64)))
