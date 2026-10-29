(import
 (snail core base))

;; A pattern can only skip a mutable field, since reading one performs mut.
(struct Counter
  ((name String)
   (count mut I64)))

(match (Counter "clicks" 0)
  ((Counter name count) count))
