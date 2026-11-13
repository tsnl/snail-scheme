(import
 (snail core base))

;; A generic function performs the row its requirement gives the class, so
;; its signature names it.
(typeclass (Store e S)
  (declare (fetch-object (left S) (right String)) (→ String) (! e)))

(define (fetch-twice (store S) (name String))
  (→ String)
  (∀ (e S))
  (⊨ (Store e S) (Copy S) (Drop (!) S))
  (string-append (fetch-object store name) (fetch-object store name)))
