;; Query: Syntax as the text the reader reads back. A producer program is
;; printed this way and its key hashes the text, and the old compiler
;; names the same file by the same key, so this writes exactly what its
;; `syntax->string` and `datum->string` write (src/snail/shell/compiler/
;; read.sld), even where that is not the only text that reads back: a
;; form's items are separated by one space, a character is written as
;; itself after `#\`, and a string escapes only a quote, a backslash and a
;; newline, so a tab or a return stays as it is, which the reader reads
;; back all the same.
(define-library (snail compiler read written)
  (export
   syntax-text
   datum-text
   text-literal)
  (import
   (snail core base)
   (snail compiler read language))
  (begin

    ;; ---- Syntax ----

    (: syntax-text (impl (Fn Syntax -> String)))
    (define (syntax-text syntax)
      (match syntax
        ((Atom datum _) (datum-text datum))
        ((Ident name _) name)
        ((Form items _) (string-append "(" (string-join (map syntax-text items) " ") ")"))))

    (: datum-text (impl (Fn Datum -> String)))
    (define (datum-text datum)
      (match datum
        ((Integer integer) (i64->string integer))
        ((Float text) text)
        ((Text text) (text-literal text))
        ((Character character) (string-append "#\\" (list->string (list character))))
        ((ByteVector bytes) (bytes-text bytes))
        ((Boolean boolean) (if boolean "#t" "#f"))))

    ;; `#u8(0 137 255)`.
    (: bytes-text (impl (Fn Bytes -> String)))
    (define (bytes-text bytes)
      (string-append "#u8("
                     (string-join (map (lambda (byte) (i64->string (i32->i64 (u8->i32 byte))))
                                       (vector->list bytes))
                                  " ")
                     ")"))

    ;; ---- Strings ----

    ;; `text` as a string literal: between quotes, with a quote, a
    ;; backslash and a newline escaped.
    (: text-literal (impl (Fn String -> String)))
    (define (text-literal text)
      (string-append "\"" (string-concatenate (map escaped (string->list text))) "\""))

    (: escaped (impl (Fn Char -> String)))
    (define (escaped c)
      (cond ((char=? c #\") "\\\"")
            ((char=? c #\\) "\\\\")
            ((char=? c #\newline) "\\n")
            (else (list->string (list c)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-written)
    (import
     (snail compiler source)
     (snail stage0 testing))
    (begin
      (define (test-written)
        (test-forms)
        (test-data)
        (test-strings))

      (define loc (Loc "t.sld" 1 1))

      ;; A form's items are separated by one space, whatever separated
      ;; them in the text, and a bracket is written as a parenthesis.
      (define (test-forms)
        (expect (syntax-text (Form (list) loc)) "()")
        (expect (syntax-text (Form (list (Ident "define" loc)
                                         (Form (list (Ident "f" loc) (Ident "x" loc)) loc)
                                         (Form (list (Form (list) loc)) loc))
                                   loc))
                "(define (f x) (()))")
        (expect (syntax-text (Ident "λ😀" loc)) "λ😀"))

      ;; Each literal as the reader would read it, a float as its text.
      (define (test-data)
        (expect (map datum-text
                     (list (Integer -7)
                           (Integer -9223372036854775808)
                           (Float "1.5e-3")
                           (Boolean #t)
                           (Boolean #f)
                           (ByteVector (list->vector (list 0 137 255)))
                           (ByteVector (list->vector (list)))))
                (list "-7" "-9223372036854775808" "1.5e-3" "#t" "#f" "#u8(0 137 255)" "#u8()"))
        (expect (map datum-text
                     (list (Character #\a) (Character #\space) (Character #\() (Character #\λ)))
                (list "#\\a" "#\\ " "#\\(" "#\\λ")))

      ;; A quote, a backslash and a newline are escaped; a tab, a return and
      ;; a `|` are not.
      (define (test-strings)
        (expect (text-literal "") "\"\"")
        (expect (text-literal "a\"b\\c\nd") "\"a\\\"b\\\\c\\nd\"")
        (expect (text-literal (list->string (list #\tab (integer->char 13) #\|)))
                (string-append "\"" (list->string (list #\tab (integer->char 13) #\|)) "\""))
        (expect (datum-text (Text "λ")) "\"λ\""))))
   (else)))
