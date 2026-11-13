(import
 (snail core base)
 (snail core io))

;; An instance writes its row in its head: closed, or ending with the row of
;; its requirements, which this instance does not have.
(typeclass (Store e S)
  (declare (fetch-object (left S) (right String)) (→ String) (! e)))

(struct Loud
  ((name String)))

(instance (Store e Loud)
  (define (fetch-object (loud Loud) (name String)) (→ String) (! e)
    name))
