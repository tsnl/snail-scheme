(import
 (snail core base)
 (snail core io))

;; A requirement that gives a closed row bounds what its type's instance
;; may perform: `peek` takes only stores whose reads are total.
(typeclass (Store e S)
  (: fetch-object (-> S String String ! e)))

(struct Directory
  ((root String)))

(instance (Store (! console) Directory)
  (define (fetch-object directory name)
    (write-line name)
    name))

(: peek (All (S) (requires (Store (!) S)) (-> S String String)))
(define (peek store name)
  (fetch-object store name))

(write-line (peek (Directory "assets") "hero"))
