(import
 (snail core base)
 (snail core io))

;; An instance's methods perform no more than the row its head writes.
(typeclass (Store e S)
  (declare (fetch-object (left S) (right String)) (→ String) (! e)))

(struct Loud
  ((name String)))

(instance (Store (!) Loud)
  (define (fetch-object (loud Loud) (name String)) (→ String)
    (write-line name)
    name))
