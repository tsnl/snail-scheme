;; An expression's literal value, which every tree from Expanded on holds:
;; a Datum, (snail compiler literals datum), under the same names, or the
;; unit value, which an `if` without an alternative has and no literal
;; writes.
(define-library (snail compiler literals constant)
  (export
   Constant
   Integer
   Float
   Text
   Character
   ByteVector
   Boolean
   UnitValue)
  (import
   (snail core base))
  (begin

    ;; ---- Constants ----

    (enum Constant
      (Integer
       ((integer I64)))
      (Float
       ((text String)))
      (Text
       ((text String)))
      (Character
       ((character Char)))
      (ByteVector
       ((bytes Bytes)))
      (Boolean
       ((boolean Bool)))
      (UnitValue))

    ))
