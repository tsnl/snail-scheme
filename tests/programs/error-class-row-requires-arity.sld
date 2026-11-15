(import
 (snail core base))

;; A requirement gives each of its class's parameters, its row among them.
(typeclass (Store E S)
  (declare (fetch-object (left S) (right String)) (→ String) (! E)))

(define (fetch-twice (store S) (name String)) (→ String) (∀ (S)) (⊨ (Store S))
  (fetch-object store name))
