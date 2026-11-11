(import
 (snail core base)
 (owned handle))

;; Only the library of a type with a Drop instance takes one apart.
(define (name-of (handle Handle)) (→ String)
  (match handle
    ((Handle name) name)))
