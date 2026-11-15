(import
 (snail core base)
 (snail core io))

;; A total function may not read from a store whose instance prints.
(typeclass (Store E S)
  (declare (fetch-object (left S) (right String)) (→ String) (! E)))

(record Directory
  ((root String)))

(instance (Store (! Output-port) Directory)
  (define (fetch-object (directory Directory) (name String)) (→ String) (! Output-port)
    (write-line name)
    name))

(define (quiet (directory Directory) (name String)) (→ String)
  (fetch-object directory name))
