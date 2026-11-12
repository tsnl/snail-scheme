;; What (snail compiler source) and the Syntax language hold, as the old
;; compiler holds it: a place, a literal and a problem. The adapter hands
;; the old checker its program and its caller its problems through these,
;; and the comparisons read them too, so they live apart from any
;; comparison.
(define-library (snail compiler adapter source)
  (export
   loc->old
   datum->old
   feedback->old)
  (import
   (snail core base)
   (snail compiler source)
   (prefix (snail compiler read language) syntax-)
   (prefix (only (snail shell compiler read)
                 Loc
                 Datum
                 DInt
                 DFloat
                 DString
                 DChar
                 DBytes
                 DBool
                 SourceDiagnostic)
           old:))
  (begin

    ;; ---- Places and problems ----

    (: loc->old (impl (Fn Loc -> old:Loc)))
    (define (loc->old loc)
      (old:Loc (::file loc) (::line loc) (::column loc)))

    (: feedback->old (impl (Fn Feedback -> old:SourceDiagnostic)))
    (define (feedback->old feedback)
      (old:SourceDiagnostic (loc->old (::loc feedback)) (::message feedback)))

    ;; ---- Literals ----

    ;; The old language has room for one more literal, the unit value,
    ;; which no reader writes.
    (: datum->old (impl (Fn syntax-Datum -> old:Datum)))
    (define (datum->old datum)
      (match datum
        ((syntax-Integer integer) (old:DInt integer))
        ((syntax-Float text) (old:DFloat text))
        ((syntax-Text text) (old:DString text))
        ((syntax-Character character) (old:DChar character))
        ((syntax-ByteVector bytes) (old:DBytes bytes))
        ((syntax-Boolean boolean) (old:DBool boolean))))

    ))
