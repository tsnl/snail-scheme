(import
 (snail core base))

;; A generic function performs the row its requirement gives the class, so
;; its signature names it.
(typeclass (Store e S)
  (: fetch-object (-> S String String ! e)))

(: fetch-twice (All (e S) (requires (Store e S) (Copy S)) (-> S String String)))
(define (fetch-twice store name)
  (string-append (fetch-object store name) (fetch-object store name)))
