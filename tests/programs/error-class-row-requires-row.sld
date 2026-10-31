(import
 (snail core base))

;; A requirement gives a class's row parameter a row: closed, as (!), or a
;; row variable.
(typeclass (Store e S)
  (: fetch-object (-> S String String ! e)))

(: fetch-twice (All (S) (requires (Store I64 S)) (-> S String String)))
(define (fetch-twice store name)
  (fetch-object store name))
