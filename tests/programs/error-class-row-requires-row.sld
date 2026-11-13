(import
 (snail core base))

;; A requirement gives a class's row parameter a row: closed, as (!), or a
;; row variable.
(typeclass (Store e S)
  (: fetch-object (Fn S String → String ! e)))

(define (fetch-twice (store S) (name String)) (→ String) (∀ S) (⊨ (Store I64 S))
  (fetch-object store name))
