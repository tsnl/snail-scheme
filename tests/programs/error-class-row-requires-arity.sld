(import
 (snail core base))

;; A requirement gives each of its class's parameters, its row among them.
(typeclass (Store e S)
  (: fetch-object (impl (Fn S String → String ! e))))

(define (fetch-twice (store S) (name String)) (→ String) (∀ S) (⊨ (Store S))
  (fetch-object store name))
