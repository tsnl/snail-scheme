(import
 (snail core base)
 (snail core io))

;; Rows are found from an instance's types, not matched, so two instances
;; for one type overlap whatever rows they write.
(typeclass (Store E S)
  (declare (fetch-object (left S) (right String)) (→ String) (! E)))

(record Loud
  ((name String)))

(instance (Store (! Output-port) Loud)
  (define (fetch-object (loud Loud) (name String)) (→ String) (! Output-port)
    (write-line name)
    name))

(instance (Store (!) Loud)
  (define (fetch-object (loud Loud) (name String)) (→ String)
    name))
