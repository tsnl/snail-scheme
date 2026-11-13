(import
 (snail core base)
 (snail core io))

;; Rows are found from an instance's types, not matched, so two instances
;; for one type overlap whatever rows they write.
(typeclass (Store e S)
  (declare (fetch-object (left S) (right String)) (→ String) (! e)))

(struct Loud
  ((name String)))

(instance (Store (! output-port) Loud)
  (define fetch-object
    (lambda (loud name) (write-line name)
            name)))

(instance (Store (!) Loud)
  (define fetch-object
    (lambda (loud name) name)))
