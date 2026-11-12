;; The read pass beside the old reader, for as long as both exist: the new
;; Syntax as the old compiler's, and three comparisons. What the two
;; readers make of a text, and the text each writes of what it read, which
;; tests/compiler.scm runs over every tracked library and over the texts
;; below; and what the two make of a producer's output, which
;; tests/compare-compiler.sld runs over every tracked library's forms as a
;; producer encodes them, and over the outputs below. The conversions and
;; the comparisons of syntax and feedback serve the later passes'
;; comparisons too. Only this folder knows both compilers, and it goes
;; when the old one does.
(define-library (snail compiler adapter read)
  (export
   syntax->old
   loc->old
   feedback->old
   items-difference
   feedback-difference
   read-difference
   malformed-texts
   unusual-texts
   misread-texts
   text-differences
   written-difference
   written-differences
   output-difference
   malformed-outputs
   output-differences)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler read pass)
   (snail compiler read written)
   (prefix (snail compiler read language) syntax-)
   (prefix (snail shell compiler read) old:))
  (begin

    ;; ---- Old syntax ----

    ;; The old Syntax for new Syntax. The old language has room for more,
    ;; a unit datum and an identifier's mark, which only its expander fills.
    (: syntax->old (impl (Fn syntax-Syntax -> old:Syntax)))
    (define (syntax->old syntax)
      (match syntax
        ((syntax-Atom datum loc) (old:Atom (datum->old datum) (loc->old loc)))
        ((syntax-Ident name loc) (old:Ident name (None) (loc->old loc)))
        ((syntax-Form items loc) (old:Form (map syntax->old items) (loc->old loc)))))

    (: datum->old (impl (Fn syntax-Datum -> old:Datum)))
    (define (datum->old datum)
      (match datum
        ((syntax-Integer integer) (old:DInt integer))
        ((syntax-Float text) (old:DFloat text))
        ((syntax-Text text) (old:DString text))
        ((syntax-Character character) (old:DChar character))
        ((syntax-ByteVector bytes) (old:DBytes bytes))
        ((syntax-Boolean boolean) (old:DBool boolean))))

    (: loc->old (impl (Fn Loc -> old:Loc)))
    (define (loc->old loc)
      (old:Loc (::file loc) (::line loc) (::column loc)))

    (: feedback->old (impl (Fn Feedback -> old:SourceDiagnostic)))
    (define (feedback->old feedback)
      (old:SourceDiagnostic (loc->old (::loc feedback)) (::message feedback)))

    ;; ---- Comparing readings ----

    ;; The first difference between what the two readers make of `text`,
    ;; the contents of `file`, if there is one. They agree when both read
    ;; the same forms at the same places, or both stop with the same
    ;; feedback.
    (: read-difference (impl (Fn String String -> (Option String))))
    (define (read-difference file text)
      (outcome-difference file
                          (read file text)
                          (old:compiling (lambda () (old:read-text text file)))))

    (: outcome-difference
       (impl (Fn String
                 (Result (List syntax-Syntax) (List Feedback))
                 (Result (List old:Syntax) old:Stop)
                 ->
                 (Option String))))
    (define (outcome-difference file new old)
      (match (Pair new old)
        ((Pair (Ok forms) (Ok old-forms)) (items-difference file (map syntax->old forms) old-forms))
        ((Pair (Err feedback) (Err (old:Failed diagnostics)))
         (feedback-difference (map feedback->old feedback) (old:diagnostics->list diagnostics)))
        ((Pair (Err feedback) (Ok _))
         (Some (string-append "only the new reader rejects it: "
                              (diagnostics-text (map feedback->old feedback)))))
        ((Pair (Ok _) (Err (old:Failed diagnostics)))
         (Some (string-append "only the old reader rejects it: "
                              (diagnostics-text (old:diagnostics->list diagnostics)))))
        ((Pair _ (Err (old:Requested _))) (Some "the old reader asked for an input"))))

    ;; ---- Comparing syntax ----

    ;; The first difference between the items the two readers read inside
    ;; `place`, a form's location or the file.
    (: items-difference (impl (Fn String (List old:Syntax) (List old:Syntax) -> (Option String))))
    (define (items-difference place news olds)
      (if (= (length news) (length olds))
          (first-difference (zip news olds))
          (Some (string-append place
                               ": the new compiler reads "
                               (i64->string (length news))
                               " items, the old "
                               (i64->string (length olds))))))

    (: first-difference (impl (Fn (List (Pair old:Syntax old:Syntax)) -> (Option String))))
    (define (first-difference pairs)
      (match pairs
        ((Nil) (None))
        ((Cons (Pair new old) more)
         (match (syntax-difference new old)
           ((None) (first-difference more))
           (found found)))))

    ;; Where `new` is, if not where `old` is, or else how it differs.
    (: syntax-difference (impl (Fn old:Syntax old:Syntax -> (Option String))))
    (define (syntax-difference new old)
      (let ((place (old:loc->string (old:syntax-loc old))))
        (if (loc=? (old:syntax-loc new) (old:syntax-loc old))
            (shape-difference place new old)
            (Some (string-append place
                                 ": the new compiler places this at "
                                 (old:loc->string (old:syntax-loc new)))))))

    ;; An identifier the old reader marked differs from any the new one
    ;; reads, which it never marks.
    (: shape-difference (impl (Fn String old:Syntax old:Syntax -> (Option String))))
    (define (shape-difference place new old)
      (match (Pair new old)
        ((Pair (old:Form news _) (old:Form olds _)) (items-difference place news olds))
        ((Pair (old:Atom datum _) (old:Atom old-datum _))
         (if (old:datum=? datum old-datum) (None) (unlike place new old)))
        ((Pair (old:Ident name _ _) (old:Ident old-name (None) _))
         (if (string=? name old-name) (None) (unlike place new old)))
        (_ (unlike place new old))))

    (: unlike (impl (Fn String old:Syntax old:Syntax -> (Option String))))
    (define (unlike place new old)
      (Some (string-append place ": the new compiler reads " (brief new) ", the old " (brief old))))

    ;; Syntax in a few words: a whole form could be a whole library.
    (: brief (impl (Fn old:Syntax -> String)))
    (define (brief syntax)
      (match syntax
        ((old:Form _ _) "a list")
        (_ (old:syntax->string syntax))))

    (: loc=? (impl (Fn old:Loc old:Loc -> Bool)))
    (define (loc=? a b)
      (and (string=? (::file a) (::file b))
           (= (::line a) (::line b))
           (= (::column a) (::column b))))

    ;; ---- Comparing feedback ----

    (: feedback-difference
       (impl (Fn (List old:SourceDiagnostic) (List old:SourceDiagnostic) -> (Option String))))
    (define (feedback-difference news olds)
      (if (same-diagnostics? news olds)
          (None)
          (Some (string-append "the new compiler says "
                               (diagnostics-text news)
                               "; the old says "
                               (diagnostics-text olds)))))

    (: same-diagnostics?
       (impl (Fn (List old:SourceDiagnostic) (List old:SourceDiagnostic) -> Bool)))
    (define (same-diagnostics? news olds)
      (and (= (length news) (length olds))
           (every? (lambda (pair) (same-diagnostic? (::first pair) (::second pair)))
                   (zip news olds))))

    (: same-diagnostic? (impl (Fn old:SourceDiagnostic old:SourceDiagnostic -> Bool)))
    (define (same-diagnostic? new old)
      (and (loc=? (::loc new) (::loc old)) (string=? (::message new) (::message old))))

    (: diagnostics-text (impl (Fn (List old:SourceDiagnostic) -> String)))
    (define (diagnostics-text diagnostics)
      (string-join (map old:diagnostic->string diagnostics) "; "))

    ;; ---- Texts ----

    ;; Texts the readers reject: each of the reader's messages, most in
    ;; more than one place.
    (: malformed-texts (List String))
    (define malformed-texts
      (list "a #| #| |#"
            "#|"
            "(a #| b"
            "'"
            "#;"
            "(a '"
            "#; #;a"
            ")"
            "a ]"
            "(#;)"
            "(')"
            "(a"
            "[a (b)"
            "(a #;(b c)"
            "(a]"
            "[a)"
            "((a) b]"
            "\"abc"
            "(a \"b"
            "\"a\\\""
            "\"\\q\""
            "\"a\\\nb\""
            "(f \"\\e\")"
            "\"\\x41\""
            "\"\\x;\""
            "\"\\xZZ;\""
            "\"\\x41 ;\""
            "#\\xZZ"
            "#\\x4G"
            "#\\"
            "(a #\\"
            "#\\foo"
            "#\\Space"
            "(#\\nope)"
            "#u8(256)"
            "#u8(1 a)"
            "#u8(1 (2))"
            "#u8(1 ])"
            "#u8(-1)"
            "#u8(1 \"2\")"
            "#u8(1 #\\a)"
            "#u8(1"
            "(#u8(1 2"
            "#u8(1 #;2"
            "#u8(1 #|"
            "."
            "(a . b)"
            "#foo"
            "#u8[1]"
            "#(1 2)"
            "#!fold-case"
            "9223372036854775808"
            "-9223372036854775809"
            "(1 99999999999999999999)"
            "😀 )"
            "(a\n  (b\n    \"\\q\"))"
            "λ\n\t)"))

    ;; Texts the readers accept that no library may write: the edges of
    ;; each lexeme and literal.
    (: unusual-texts (List String))
    (define unusual-texts
      (list ""
            " \n\t"
            "; only a comment"
            "#| a |#"
            "#|# |#"
            "#;a"
            "#; #; a b c"
            "'a"
            "''a"
            "[a (b) [c]]"
            "#u8()"
            "#u8( 0 255 )"
            "#u8(1 #;2 3 #|4|# 5)"
            "#u8(007)"
            "#\\x"
            "#\\("
            "#\\)"
            "#\\ "
            "#\\space"
            "#\\x41"
            "#\\λ"
            "\"\""
            "\"\\\\\\\"\\|\""
            "\"\\x1F600;\""
            "\"a\\tb\\rc\\0d\\ne\""
            "+5"
            "-0"
            "1."
            ".5"
            "1e9"
            "1E-3"
            "-"
            "..."
            "1+"
            "#true"
            "#false"
            "a;b"
            "a'b"
            "a\"b\""
            "-9223372036854775808"
            "9223372036854775807"
            "λ😀 \"é\""
            "#\\x10FFFF"
            "\"\\xD7FF;\\xE000;\""
            "a\xA0;b"
            "\x3000; x"
            "a\x0C;b"
            "(\x660; 1\x660; -\x660;)"))

    ;; Texts the old reader gets wrong, so the comparison cannot judge
    ;; them: it accumulates a hexadecimal escape's digits without bound and
    ;; makes a character of any code, so it accepts a surrogate or a code
    ;; past 10FFFF, and with more digits overflows I64 when compiled and
    ;; fails inside Chibi's `integer->char`. Each is checked only for the
    ;; new reader's verdict, the one message it stops with.
    (: misread-texts (List (Pair String String)))
    (define misread-texts
      (list (Pair "#\\xD800" "invalid hexadecimal escape")
            (Pair "#\\xDFFF" "invalid hexadecimal escape")
            (Pair "#\\x110000" "invalid hexadecimal escape")
            (Pair "#\\x1000000000000000041" "invalid hexadecimal escape")
            (Pair "\"\\xD800;\"" "invalid hexadecimal escape")
            (Pair "\"\\x110000;\"" "invalid hexadecimal escape")
            (Pair "\"\\x12345678901234567890;\"" "invalid hexadecimal escape")))

    ;; What is wrong when the readers are compared on these texts: a
    ;; malformed text the new reader accepts, an unusual one it rejects, a
    ;; text the two read differently, or a misread one that the new reader
    ;; does not stop with its verdict.
    (: text-differences (impl (Fn -> (List String))))
    (define (text-differences)
      (concatenate (list (concatenate (map malformed-difference malformed-texts))
                         (concatenate (map unusual-difference unusual-texts))
                         (concatenate (map misread-difference misread-texts)))))

    (: malformed-difference (impl (Fn String -> (List String))))
    (define (malformed-difference text)
      (if (accepts? text)
          (list (string-append (quoted text) ": the new reader accepts it"))
          (reading-difference text)))

    (: unusual-difference (impl (Fn String -> (List String))))
    (define (unusual-difference text)
      (if (accepts? text)
          (reading-difference text)
          (list (string-append (quoted text) ": the new reader rejects it"))))

    (: misread-difference (impl (Fn (Pair String String) -> (List String))))
    (define (misread-difference entry)
      (match (read "text.sld" (::first entry))
        ((Err (Cons (Feedback _ message) (Nil)))
         (if (string=? message (::second entry)) (Nil) (list (wrong-verdict entry))))
        (_ (list (wrong-verdict entry)))))

    (: wrong-verdict (impl (Fn (Pair String String) -> String)))
    (define (wrong-verdict entry)
      (string-append (quoted (::first entry))
                     ": the new reader should stop with "
                     (::second entry)))

    (: reading-difference (impl (Fn String -> (List String))))
    (define (reading-difference text)
      (match (read-difference "text.sld" text)
        ((Some difference) (list (string-append (quoted text) ": " difference)))
        ((None) (Nil))))

    (: accepts? (impl (Fn String -> Bool)))
    (define (accepts? text)
      (match (read "text.sld" text)
        ((Ok _) #t)
        ((Err _) #f)))

    ;; A text as a string literal, escapes and all.
    (: quoted (impl (Fn String -> String)))
    (define (quoted text)
      (old:datum->string (old:DString text)))

    ;; ---- Comparing written text ----

    ;; The first form of `text`, the contents of `file`, whose text the
    ;; new compiler writes otherwise than the old, when both read it. A
    ;; producer's key hashes this text, so the two must agree exactly.
    (: written-difference (impl (Fn String String -> (Option String))))
    (define (written-difference file text)
      (match (Pair (read file text) (old:compiling (lambda () (old:read-text text file))))
        ((Pair (Ok forms) (Ok old-forms))
         (first-written-difference
          (zip (map syntax-text forms) (map old:syntax->string old-forms))))
        (_ (None))))

    (: first-written-difference (impl (Fn (List (Pair String String)) -> (Option String))))
    (define (first-written-difference texts)
      (match texts
        ((Nil) (None))
        ((Cons (Pair new old) rest)
         (if (string=? new old)
             (first-written-difference rest)
             (Some
              (string-append "the new compiler writes " (quoted new) ", the old " (quoted old)))))))

    ;; What is wrong when the text the readers read from the texts above
    ;; is written by both.
    (: written-differences (impl (Fn -> (List String))))
    (define (written-differences)
      (concatenate (map (lambda (text)
                          (match (written-difference "text.sld" text)
                            ((Some difference) (list (string-append (quoted text) ": " difference)))
                            ((None) (Nil))))
                        unusual-texts)))

    ;; ---- Comparing producers' outputs ----

    ;; The first difference between what `read-generated` and the old
    ;; `decode-syntax` make of a producer's output, `bytes`, placed at
    ;; `loc`: the same form, or the same feedback.
    (: output-difference (impl (Fn Bytes Loc -> (Option String))))
    (define (output-difference bytes loc)
      (outcome-difference (::file loc)
                          (match (read-generated bytes loc)
                            ((Ok form) (Ok (list form)))
                            ((Err feedback) (Err feedback)))
                          (old:compiling (lambda ()
                                           (list (old:decode-syntax bytes (loc->old loc)))))))

    ;; Outputs the old decoder refuses: each of its messages, most in more
    ;; than one place.
    (: malformed-outputs (List (List I64)))
    (define malformed-outputs
      (list (list)
            (list 0)
            (list 0 2 1 1 102)
            (list 1 3 97)
            (list 7 3 1 2)
            (list 1 128)
            (list 5 5)
            (list 0 0 0)
            (list 8)
            (list 255)
            (list 0 1 9)
            (list 1 128 128 128 128 128 1)
            (list 0 255 255 255 255 255 1)
            (list 4 128 176 3)
            (list 4 255 191 3)
            (list 3 1 128 128 68)
            (list 2 1 120)
            (list 2 0)
            (list 2 1 45)
            (list 2 3 49 46 46)
            (list 2 2 35 116)
            (list 2 19 57 50 50 51 51 55 50 48 51 54 56 53 52 55 55 53 56 48 56)))

    ;; What is wrong when the decoders are compared on the outputs above.
    (: output-differences (impl (Fn -> (List String))))
    (define (output-differences)
      (concatenate (map (lambda (codes)
                          (match (output-difference (codes-bytes codes) (Loc "recipe.sld" 3 4))
                            ((Some difference)
                             (list (string-append (codes-text codes) ": " difference)))
                            ((None) (Nil))))
                        malformed-outputs)))

    (: codes-bytes (impl (Fn (List I64) -> Bytes)))
    (define (codes-bytes codes)
      (list->vector (map (lambda (code) (i32->u8 (i64->i32 code))) codes)))

    (: codes-text (impl (Fn (List I64) -> String)))
    (define (codes-text codes)
      (string-append "#u8(" (string-join (map i64->string codes) " ") ")"))

    ))
