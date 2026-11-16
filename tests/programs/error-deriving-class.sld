(import
 (snail core base))
;; Only the classes whose libraries define a deriving macro can be derived.
(record Point
  ((x I64))
  (deriving Show))
