;; Syntax, the language `read` writes: a file's text as located forms.
;;
;;   Syntax ::= Atom Datum | Ident name | Form Syntax*
;;   Datum  ::= Integer integer | Float text | Text text | Character character
;;            | ByteVector bytes | Boolean boolean
;;
;; Over the text it comes from, Syntax guarantees that every bracket is
;; matched, that `'d` is the form `(quote d)`, that each literal's value is
;; decoded and an integer fits in I64, and that every node knows where it
;; starts. A float keeps its text, which only the backend interprets; a
;; Text holds the characters a string literal stands for.
(define-library (snail compiler read language)
  (export
   Syntax
   Atom
   Ident
   Form
   Datum
   Integer
   Float
   Text
   Character
   ByteVector
   Boolean)
  (import
   (snail core base)
   (snail compiler source))
  (begin

    ;; ---- Syntax ----

    ;; A node's location is where it starts: a form's is its opening
    ;; bracket.
    (enum Syntax
      (Atom
       ((datum Datum)
        (loc Loc)))
      (Ident
       ((name String)
        (loc Loc)))
      (Form
       ((items (List Syntax))
        (loc Loc))))

    (enum Datum
      (Integer ((integer I64)))
      (Float ((text String)))
      (Text ((text String)))
      (Character ((character Char)))
      (ByteVector ((bytes Bytes)))
      (Boolean ((boolean Bool))))

    ))
