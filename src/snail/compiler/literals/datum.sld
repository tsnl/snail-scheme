;; A literal as the reader decodes it, which Syntax holds in an atom and a
;; pattern holds as the value it matches. An integer fits in I64. A float
;; keeps its text, which only the backend interprets; a Text holds the
;; characters a string literal stands for. Its constructors share
;; Constant's names, (snail compiler literals constant), so a library that
;; holds both imports Datum under the prefix `datum-`.
(define-library (snail compiler literals datum)
  (export
   Datum
   Integer
   Float
   Text
   Character
   ByteVector
   Boolean)
  (import
   (snail core base))
  (begin

    ;; ---- Literals ----

    (enum Datum
      (Integer ((integer I64)))
      (Float ((text String)))
      (Text ((text String)))
      (Character ((character Char)))
      (ByteVector ((bytes Bytes)))
      (Boolean ((boolean Bool))))

    ))
