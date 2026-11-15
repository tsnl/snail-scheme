(import
 (snail core base)
 (snail core io))

;; A requirement that gives a closed row bounds what its type's instance
;; may perform: `peek` takes only stores whose reads are total.
(typeclass (Store E S)
  (declare (fetch-object (left S) (right String)) (→ String) (! E)))

(record Directory
  ((root String)))

(instance (Store (! Output-port) Directory)
  (define (fetch-object (directory Directory) (name String)) (→ String) (! Output-port)
    (write-line name)
    name))

(define (peek (store S) (name String)) (→ String) (∀ (S)) (⊨ (Store (!) S))
  (fetch-object store name))

(define main
  (lambda ()
    (write-line (peek (new Directory (root "assets")) "hero"))
    (unit)))
