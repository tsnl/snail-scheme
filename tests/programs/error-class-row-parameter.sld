(import
 (snail core base))
;; A class parameter is a type: a method writes the row it performs.
(typeclass (Store e S)
  (declare (fetch (store S) (key String)) (→ String) (! e)))
