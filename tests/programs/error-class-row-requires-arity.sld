(import
 (snail core base))

;; A requirement gives each of its class's parameters, its row among them.
(typeclass (Store e S)
  (: fetch-object (impl (Fn S String -> String ! e))))

(: fetch-twice (All (S) (requires (Store S)) (impl (Fn S String -> String))))
(define (fetch-twice store name)
  (fetch-object store name))
