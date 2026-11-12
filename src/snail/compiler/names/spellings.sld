;; The text a Global is spelled as, where the compiler puts a name into
;; the program it writes. The compiler never looks a name up by its
;; text, nor learns anything by reading one: a name is data, compared as
;; its library, name and serial. Two texts are data a running program
;; holds, and must be spelled as the old compiler spells them, or a
;; program would read them differently: a case's wire schema, whose hash
;; is the TypeId wire data carries (snail compiler declare identities),
;; and the texts the code `dispatch` writes puts in a CastError (snail
;; compiler dispatch text). Both spell a Global here.
;;
;; A Global is spelled as the old compiler's unique name: its library's
;; parts joined by dots, a colon and its name; a builtin of (snail core
;; forms) by its name alone. Its short spelling is its name alone, as the
;; old compiler's short name is the text after the last colon of the
;; unique name; a name that holds a colon is spelled whole, since nothing
;; here reads a name's text. A Global a macro's template wrote has a serial
;; of its own, and the old name holds the stamp of the macro's use, which
;; no new pass has, so it is spelled `name%serial`, which matches no old
;; name.
(define-library (snail compiler names spellings)
  (export
   global-spelling
   short-spelling)
  (import
   (snail core base)
   (snail compiler names libraries)
   (only (snail compiler names globals) Global))
  (begin

    ;; ---- Spellings ----

    (: global-spelling (impl (Fn Global -> String)))
    (define (global-spelling global)
      (if (and (same-library? (::library global) forms-library) (= (::serial global) 0))
          (::name global)
          (string-append (library-key (::library global)) ":" (short-spelling global))))

    ;; A Global by its name within its library.
    (: short-spelling (impl (Fn Global -> String)))
    (define (short-spelling global)
      (if (= (::serial global) 0)
          (::name global)
          (string-append (::name global) "%" (i64->string (::serial global)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-spellings)
    (import
     (snail stage0 testing))
    (begin
      (define (test-spellings)
        (let ((base (list "snail" "core" "base")))
          (expect (global-spelling (Global base "Option" 0)) "snail.core.base:Option")
          (expect (global-spelling (Global base "+" 0)) "snail.core.base:+")
          (expect (global-spelling (Global forms-library "I64" 0)) "I64")
          (expect (global-spelling (Global (list "main") "Box" 3)) "main:Box%3")
          (expect (map short-spelling
                       (list (Global base "List" 0)
                             (Global forms-library "I64" 0)
                             (Global (list "main") "Box" 12)
                             (Global (list "main") "a:b" 0)))
                  (list "List" "I64" "Box%12" "a:b"))))))
   (else)))
