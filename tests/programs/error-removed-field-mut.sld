(import
 (snail core base))

;; All fields are mutable; the old per-field annotation is gone.
(record Counter
  ((count mut I64)))
