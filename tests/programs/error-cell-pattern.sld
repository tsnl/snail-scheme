(import
 (snail core base))

;; A pattern can only skip a cell's content, since reading it performs mut.
(match (ref 1)
  ((Ref content) content))
