(import
 (snail core base)
 (snail core io))

;; An instance's methods perform no more than the row its head writes.
(typeclass (Store e S)
  (: fetch-object (-> S String String ! e)))

(struct Loud
  ((name String)))

(instance (Store (!) Loud)
  (define (fetch-object loud name)
    (write-line name)
    name))
