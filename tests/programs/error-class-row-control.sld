(import
 (snail core base)
 (snail core io))

;; A method's row names no control effect: its specializations are not
;; told apart by what its instance performs.
(effect Gen
  ((ctl next (-> Unit))))
(typeclass (Store e S)
  (: fetch-object (-> S String String ! e)))

(struct Loud
  ((name String)))

(instance (Store (! Gen) Loud)
  (define (fetch-object loud name)
    (next)
    name))
