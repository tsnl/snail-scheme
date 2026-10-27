(import
 (snail-core base)
 (snail-core io))

;; A Holder is affine: it has a Once field. Matching it with `_` for that
;; field names an owner for the wildcard, so it can be dropped.
(struct Holder
  ((work (Once (-> Unit ! console)))))

(match (Holder (once (lambda () (write-line "a"))))
  ((Holder _) (write-line "first")))

(match (Holder (once (lambda () (write-line "b"))))
  ((Holder _) (write-line "second")))
