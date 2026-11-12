;; Syntax, the language `read` writes: a file's text as located forms.
;;
;;   Syntax ::= Atom Datum | Ident name | Form Syntax*
;;
;; Datum is the vocabulary's, (snail compiler literals datum).
;;
;; Over the text it comes from, Syntax guarantees that every bracket is
;; matched, that `'d` is the form `(quote d)`, that each literal's value is
;; decoded and an integer fits in I64, and that every node knows where it
;; starts.
(define-library (snail compiler read language)
  (export
   Syntax
   Atom
   Ident
   Form)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler literals datum) Datum))
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

    ))
