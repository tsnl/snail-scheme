;; Query: the texts the code `dispatch` writes puts into the running
;; program, which a program reads from the CastError a failed dispatch
;; raises: each type it expected, as the vocabulary (snail compiler types
;; text) writes it, the place as the old compiler writes a Loc
;; (`loc->string`, src/snail/shell/compiler/read.sld), and the method as
;; its unique name, as (snail compiler names spellings) spells it. These
;; texts are display, as a message is: the running program shows them and
;; compares them, and the compiler never reads one back.
(define-library (snail compiler dispatch text)
  (export
   place-text
   member-text)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler declare language) Member ClassMethod FieldReader)
   (only (snail compiler names spellings) global-spelling))
  (begin

    ;; ---- Names ----

    ;; The method a dispatched call names: a class's method by its unique
    ;; name, or a field class's reader by its label's path.
    (: member-text (impl (Fn Member -> String)))
    (define (member-text member)
      (match member
        ((ClassMethod global) (global-spelling global))
        ((FieldReader label) (string-append "::" label))))

    ;; ---- Places ----

    ;; A place in line 0 is its file as a whole.
    (: place-text (impl (Fn Loc -> String)))
    (define (place-text loc)
      (if (= (::line loc) 0)
          (::file loc)
          (string-append (::file loc)
                         ":"
                         (i64->string (::line loc))
                         ":"
                         (i64->string (::column loc)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-text)
    (import
     (only (snail compiler names globals) Global)
     (snail stage0 testing))
    (begin
      (define (test-text)
        (test-names)
        (test-places))

      (define main (list "main"))

      ;; A class's method by its unique name, a field class's reader by its
      ;; path.
      (define (test-names)
        (expect (member-text (ClassMethod (Global main "combine" 4))) "main:combine%4")
        (expect (member-text (ClassMethod (Global main "combine" 0))) "main:combine")
        (expect (member-text (FieldReader "x")) "::x"))

      ;; Read off `loc->string`.
      (define (test-places)
        (expect (place-text (Loc "t.sld" 3 7)) "t.sld:3:7")
        (expect (place-text (Loc "t.sld" 0 0)) "t.sld"))))
   (else)))
