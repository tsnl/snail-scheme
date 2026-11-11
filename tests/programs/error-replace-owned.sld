(import
 (snail core base)
 (owned handle))

;; Only the library of a type with a Drop instance replaces its fields.
(define (rename (handle Handle)) (→ Handle)
  (Handle-name-set handle "renamed"))
