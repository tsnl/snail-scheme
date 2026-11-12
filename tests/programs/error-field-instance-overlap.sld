(import
 (snail core base))

;; A struct with no mutable field has an instance of each field's class,
;; which joins its class where the struct is declared. An instance written
;; after it is compared with it; field-instance-before-struct.sld writes
;; one before it.
(struct Point
  ((x I64)))
(instance (::x Point I64)
  (define (::x point) 1))
