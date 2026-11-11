(import
 (snail core base)
 (owned handle))

;; Only the library of a type with a Drop instance replaces its fields.
(: rename (impl (Fn Handle -> Handle)))
(define (rename handle)
  (Handle-name-set handle "renamed"))
