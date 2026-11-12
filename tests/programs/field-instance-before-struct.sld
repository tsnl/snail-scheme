(import
 (snail core base)
 (snail core io))

;; A struct's field instance joins its class without being compared with the
;; instances before it, so an instance of the field's class written before
;; the struct is accepted; error-field-instance-overlap.sld writes one after.
;; A read chooses the first instance that matches, the one written here.
(instance (::x Point I64)
  (define (::x point) 1))
(struct Point
  ((x I64)))
(display (ann (::x (Point 5)) I64))
(newline)
