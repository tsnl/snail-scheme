(import
 (snail core base)
 (owned handle))

;; Only the library of a type with a Drop instance takes one apart.
(: name-of (-> Handle String))
(define (name-of handle)
  (match handle
    ((Handle name) name)))
