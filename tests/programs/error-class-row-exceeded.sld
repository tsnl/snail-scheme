(import
 (snail core base)
 (snail core io))

;; A total function may not read from a store whose instance prints.
(typeclass (Store e S)
  (: fetch-object (impl (Fn S String → String ! e))))

(struct Directory
  ((root String)))

(instance (Store (! output-port) Directory)
  (define fetch-object
    (lambda (directory name) (write-line name)
            name)))

(define (quiet (directory Directory) (name String)) (→ String)
  (fetch-object directory name))
