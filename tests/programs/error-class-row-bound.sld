(import
 (snail core base)
 (snail core io))

;; A requirement that gives a closed row bounds what its type's instance
;; may perform: `peek` takes only stores whose reads are total.
(typeclass (Store e S)
  (declare (fetch-object (left S) (right String)) (→ String) (! e)))

(struct Directory
  ((root String)))

(instance (Store (! output-port) Directory)
  (define fetch-object
    (lambda (directory name) (write-line name)
            name)))

(define (peek (store S) (name String)) (→ String) (∀ (S)) (⊨ (Store (!) S))
  (fetch-object store name))

(define main
  (lambda ()
    (write-line (peek (Directory "assets") "hero"))
    (unit)))
