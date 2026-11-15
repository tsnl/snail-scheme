(import
 (snail core base))

;; A requirement gives a class's row parameter a row: closed, as (!), or a
;; row variable.
(typeclass (Store E S)
  (declare (fetch-object (left S) (right String)) (→ String) (! E)))

(define (fetch-twice (store S) (name String)) (→ String) (∀ (S)) (⊨ (Store I64 S))
  (fetch-object store name))
