(import
 (snail core base)
 (snail core io))

;; An instance gives each of its class's parameters, its row among them.
(typeclass (Store e S)
  (: fetch-object (impl (Fn S String -> String ! e))))

(struct Loud
  ((name String)))

(instance (Store Loud)
  (define (fetch-object loud name)
    name))
