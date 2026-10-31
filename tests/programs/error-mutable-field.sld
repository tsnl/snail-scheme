(import
 (snail core base))

;; Only Ref has a mutable field. A struct is a value; one a program changes
;; lives in a cell.
(struct Counter
  ((count mut I64)))
