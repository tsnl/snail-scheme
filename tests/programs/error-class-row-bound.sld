(import
 (snail core base)
 (snail core io))

;; A requirement that gives a closed row bounds what its type's instance
;; may perform: `peek` takes only stores whose reads are total.
(typeclass (Store e S)
  (: fetch-object (impl (Fn S String → String ! e))))

(struct Directory
  ((root String)))

(instance (Store (! output-port) Directory)
  (define fetch-object
    (lambda (directory name) (write-line name)
            name)))

(define (peek (store S) (name String)) (→ String) (∀ S) (⊨ (Store (!) S))
  (fetch-object store name))

(write-line (peek (Directory "assets") "hero"))
