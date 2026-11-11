;; The pass `read`: a file's text becomes its located forms, in the Syntax
;; language. The reader is a recursive descent over the file's
;; characters, held in a vector so that a position is an index. The
;; lexical rules say what starts at an index and where it ends, the
;; literal rules what a literal's text stands for, and the line table where
;; an index is; this library decides only how lexemes make data. Reading
;; stops at the first problem, so a failure holds one piece of feedback.
(define-library (snail compiler read pass)
  (export
   read)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler read language)
   (snail compiler read lexemes)
   (snail compiler read lines)
   (snail compiler read literals))
  (begin

    ;; ---- Sources ----

    ;; A file being read: its characters, and where its lines start.
    (struct Source
      ((chars (Vector Char))
       (lines Lines)))

    ;; What reading a part of the text answers: the value read and the
    ;; index just after it, or what stopped the reader.
    (type (Reading T) (Result (Scanned T) (List Feedback)))

    (: source-loc (impl (Fn Source I64 -> Loc)))
    (define (source-loc source index)
      (loc-at (::lines source) index))

    (: source-text (impl (Fn Source I64 I64 -> String)))
    (define (source-text source start end)
      (vector->string (subvector (::chars source) start end)))

    ;; ---- Files ----

    (: read (impl (Fn String String -> (Result (List Syntax) (List Feedback)))))
    (define (read file text)
      (let ((chars (string->vector text)))
        (read-forms (Source chars (lines-of file chars)) 0 (Nil))))

    ;; The forms from `index` to the end of the text, after the `forms`
    ;; before them, which come latest first.
    (: read-forms
       (impl (Fn Source I64 (List Syntax) -> (Result (List Syntax) (List Feedback)))))
    (define (read-forms source index forms)
      (result-let* ((start (skip-atmosphere source index)))
        (if (= start (vector-length (::chars source)))
            (Ok (reverse forms))
            (result-let* ((form (read-datum source start)))
              (read-forms source (::end form) (Cons (::value form) forms))))))

    ;; ---- Atmosphere ----

    ;; The index of the first lexeme at or after `index`, past whitespace,
    ;; comments, and the data that `#;` comments out. Such a datum is read
    ;; in order to be skipped, so a problem in it stops the reader too.
    (: skip-atmosphere (impl (Fn Source I64 -> (Result I64 (List Feedback)))))
    (define (skip-atmosphere source index)
      (match (atmosphere-at (::chars source) index)
        ((None) (Ok index))
        ((Some (Scanned (BlockComment #f) end))
         (fail (source-loc source end) "unterminated block comment"))
        ((Some (Scanned (DatumComment) end))
         (result-let* ((skipped (read-datum source end)))
           (skip-atmosphere source (::end skipped))))
        ((Some (Scanned _ end)) (skip-atmosphere source end))))

    ;; ---- Data ----

    ;; The datum that the first lexeme at or after `index` begins.
    (: read-datum (impl (Fn Source I64 -> (Reading Syntax))))
    (define (read-datum source index)
      (result-let* ((start (skip-atmosphere source index)))
        (read-lexeme source start (lexeme-at (::chars source) start))))

    ;; The datum that `lexeme`, found at `start`, begins. A datum is
    ;; located where it starts.
    (: read-lexeme (impl (Fn Source I64 (Scanned Lexeme) -> (Reading Syntax))))
    (define (read-lexeme source start lexeme)
      (let ((loc (source-loc source start))
            (end (::end lexeme)))
        (match (::value lexeme)
          ((EndOfText) (fail loc "expected a datum before the end of the file"))
          ((ListClose _) (fail loc "unexpected closing parenthesis"))
          ((ListOpen close) (read-list source end close loc (Nil)))
          ((QuoteMark) (read-quote source end loc))
          ((BytesOpen) (read-bytes source end loc (Nil)))
          ((StringLexeme closed) (read-string source start end closed loc))
          ((CharacterLexeme) (read-character source start end loc))
          ((TokenLexeme) (read-token source start end loc)))))

    ;; ---- Lists ----

    ;; The rest of a list opened at `loc` that the bracket `close` closes:
    ;; the items from `index` on, after the `items` before them, which come
    ;; latest first.
    (: read-list (impl (Fn Source I64 Char Loc (List Syntax) -> (Reading Syntax))))
    (define (read-list source index close loc items)
      (result-let* ((start (skip-atmosphere source index)))
        (let ((lexeme (lexeme-at (::chars source) start)))
          (match (::value lexeme)
            ((EndOfText) (fail loc "unclosed list"))
            ((ListClose bracket)
             (if (char=? bracket close)
                 (Ok (Scanned (Form (reverse items) loc) (::end lexeme)))
                 (fail (source-loc source start) "mismatched closing parenthesis")))
            (_ (result-let* ((item (read-lexeme source start lexeme)))
                 (read-list source (::end item) close loc (Cons (::value item) items))))))))

    ;; `'datum` reads as `(quote datum)`, and the form and its `quote` are
    ;; both at the quote mark, `loc`.
    (: read-quote (impl (Fn Source I64 Loc -> (Reading Syntax))))
    (define (read-quote source index loc)
      (result-let* ((quoted (read-datum source index)))
        (Ok (Scanned (Form (list (Ident "quote" loc) (::value quoted)) loc) (::end quoted)))))

    ;; ---- Byte vectors ----

    ;; The rest of a byte vector opened at `loc`: the bytes from `index` to
    ;; its closing parenthesis, after the `bytes` before them, which come
    ;; latest first. Atmosphere separates bytes as it does data. A byte is
    ;; the text up to a delimiter, so a list, a string or a `]` where a byte
    ;; belongs is an empty byte, and a problem.
    (: read-bytes (impl (Fn Source I64 Loc (List U8) -> (Reading Syntax))))
    (define (read-bytes source index loc bytes)
      (result-let* ((start (skip-atmosphere source index)))
        (match (lexeme-at (::chars source) start)
          ((Scanned (EndOfText) _) (fail loc "unclosed byte vector"))
          ((Scanned (ListClose #\)) end)
           (Ok (Scanned (Atom (ByteVector (list->vector (reverse bytes))) loc) end)))
          (_ (let ((end (token-end (::chars source) start)))
               (result-let* ((byte (placed (source-loc source start)
                                           (byte-value (source-text source start end)))))
                 (read-bytes source end loc (Cons byte bytes))))))))

    ;; ---- Literals ----

    ;; A string from the quote at `start` to `end`, which is just after
    ;; its closing quote if it is `closed`.
    (: read-string (impl (Fn Source I64 I64 Bool Loc -> (Reading Syntax))))
    (define (read-string source start end closed loc)
      (if closed
          (result-let* ((text
                         (placed loc (string-value (source-text source (+ start 1) (- end 1))))))
            (Ok (Scanned (Atom (Text text) loc) end)))
          (fail loc "unterminated string")))

    ;; A character from the `#\` at `start` to `end`.
    (: read-character (impl (Fn Source I64 I64 Loc -> (Reading Syntax))))
    (define (read-character source start end loc)
      (result-let* ((character
                     (placed loc (character-value (source-text source (+ start 2) end)))))
        (Ok (Scanned (Atom (Character character) loc) end))))

    (: read-token (impl (Fn Source I64 I64 Loc -> (Reading Syntax))))
    (define (read-token source start end loc)
      (result-let* ((syntax (token-syntax (source-text source start end) loc)))
        (Ok (Scanned syntax end))))

    ;; A token is a boolean, a number or a name, or a problem.
    (: token-syntax (impl (Fn String Loc -> (Result Syntax (List Feedback)))))
    (define (token-syntax token loc)
      (match (token-kind token)
        ((BooleanToken boolean) (Ok (Atom (Boolean boolean) loc)))
        ((IntegerToken)
         (result-let* ((integer (placed loc (integer-value token))))
           (Ok (Atom (Integer integer) loc))))
        ((FloatToken) (Ok (Atom (Float token) loc)))
        ((NameToken) (Ok (Ident token loc)))
        ((InvalidToken problem) (fail loc problem))))

    ;; A literal's value, or its problem placed at `loc`.
    (: placed (All (T) (impl (Fn Loc (Result T String) -> (Result T (List Feedback))))))
    (define (placed loc decoded)
      (match decoded
        ((Ok value) (Ok value))
        ((Err problem) (fail loc problem))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-read)
    (import
     (snail stage0 testing))
    (begin
      (define (test-read)
        (test-forms)
        (test-locations)
        (test-atmosphere)
        (test-lists)
        (test-literals)
        (test-tokens)
        (test-byte-vectors)
        (test-problems-inside))

      ;; ---- Helpers ----

      ;; What `text` reads as, written back as text, or the feedback that
      ;; stopped the reader.
      (define (read-back text)
        (match (read "t" text)
          ((Ok forms) (Ok (map written forms)))
          ((Err feedback) (Err feedback))))

      ;; Syntax as source text, with brackets as parentheses. A string is
      ;; written without escapes; the cases that need them compare syntax.
      (define (written syntax)
        (match syntax
          ((Atom datum _) (written-datum datum))
          ((Ident name _) name)
          ((Form items _) (string-append "(" (string-join (map written items) " ") ")"))))

      (define (written-datum datum)
        (match datum
          ((Integer integer) (i64->string integer))
          ((Float text) text)
          ((Text text) (string-append "\"" text "\""))
          ((Character character) (string-append "#\\" (list->string (list character))))
          ((ByteVector bytes)
           (string-append "#u8("
                          (string-join (map (lambda (byte) (i64->string (i32->i64 (u8->i32 byte))))
                                            (vector->list bytes))
                                       " ")
                          ")"))
          ((Boolean boolean) (if boolean "#t" "#f"))))

      ;; The one piece of feedback that stops reading `text` in the file
      ;; "t".
      (define (problem line column message)
        (fail (Loc "t" line column) message))

      ;; ---- Cases ----

      ;; Brackets of either shape make the same form, and a quote mark
      ;; makes a quotation.
      (define (test-forms)
        (expect (read-back "") (Ok (list)))
        (expect (read-back "(define [f x] (+ x 1.5)) 'x '(a) ''b")
                (Ok
                 (list "(define (f x) (+ x 1.5))" "(quote x)" "(quote (a))" "(quote (quote b))")))
        (expect (read-back "() [] (())") (Ok (list "()" "()" "(())")))
        (expect (read "t" "(a 1)")
                (Ok (list (Form (list (Ident "a" (Loc "t" 1 2)) (Atom (Integer 1) (Loc "t" 1 4)))
                                (Loc "t" 1 1))))))

      ;; A datum is at the line and column where it starts, a column counts
      ;; characters, and a quotation and its `quote` are at the quote mark.
      (define (test-locations)
        (expect (read "t.sld" "\n  (a\n   b)")
                (Ok (list (Form (list (Ident "a" (Loc "t.sld" 2 4)) (Ident "b" (Loc "t.sld" 3 4)))
                                (Loc "t.sld" 2 3)))))
        (expect (read "t" "λ😀 \"é\"")
                (Ok (list (Ident "λ😀" (Loc "t" 1 1)) (Atom (Text "é") (Loc "t" 1 4)))))
        (expect (read "t" " 'x")
                (Ok (list (Form (list (Ident "quote" (Loc "t" 1 2)) (Ident "x" (Loc "t" 1 3)))
                                (Loc "t" 1 2)))))
        (expect (read "λ😀.sld" "😀 )")
                (fail (Loc "λ😀.sld" 1 3) "unexpected closing parenthesis")))

      ;; Comments nest, `#;` comments out a whole datum, and atmosphere
      ;; alone reads as no forms.
      (define (test-atmosphere)
        (expect (read-back " \t\n ; a note") (Ok (list)))
        (expect (read-back "a ; note\nb") (Ok (list "a" "b")))
        (expect (read-back "a #| #| |# |# b") (Ok (list "a" "b")))
        (expect (read-back "#;(skip (this)) a #; b c") (Ok (list "a" "c")))
        (expect (read-back "#; #; a b c") (Ok (list "c")))
        (expect (read-back "(a #;b)") (Ok (list "(a)")))
        (expect (read-back "a #| #| |#") (problem 1 11 "unterminated block comment"))
        (expect (read-back "#;") (problem 1 3 "expected a datum before the end of the file"))
        (expect (read-back "(#;)") (problem 1 4 "unexpected closing parenthesis")))

      ;; A list closes with the bracket that opened it.
      (define (test-lists)
        (expect (read-back "(a") (problem 1 1 "unclosed list"))
        (expect (read-back "(a (b)") (problem 1 1 "unclosed list"))
        (expect (read-back "(a]") (problem 1 3 "mismatched closing parenthesis"))
        (expect (read-back "[a)") (problem 1 3 "mismatched closing parenthesis"))
        (expect (read-back "a )") (problem 1 3 "unexpected closing parenthesis"))
        (expect (read-back "]") (problem 1 1 "unexpected closing parenthesis"))
        (expect (read-back "'") (problem 1 2 "expected a datum before the end of the file"))
        (expect (read-back "(')") (problem 1 3 "unexpected closing parenthesis")))

      ;; A string or character is at its quote or `#\`.
      (define (test-literals)
        (expect (read "t" "\"a\\nb\" \"\\x41;\\\"\" #\\a #\\space #\\( #\\x41 #\\x")
                (Ok (list (Atom (Text "a\nb") (Loc "t" 1 1))
                          (Atom (Text "A\"") (Loc "t" 1 8))
                          (Atom (Character #\a) (Loc "t" 1 18))
                          (Atom (Character #\space) (Loc "t" 1 22))
                          (Atom (Character #\() (Loc "t" 1 30))
                          (Atom (Character #\A) (Loc "t" 1 34))
                          (Atom (Character #\x) (Loc "t" 1 40)))))
        (expect (read-back "(a \"b") (problem 1 4 "unterminated string"))
        (expect (read-back " \"\\q\"") (problem 1 2 "unknown string escape"))
        (expect (read-back "\"\\x41\" ;") (problem 1 1 "invalid hexadecimal escape"))
        (expect (read-back "#\\") (problem 1 1 "expected a character after #\\"))
        (expect (read-back "(#\\nope)") (problem 1 2 "unknown character name nope"))
        (expect (read-back "#\\xZZ") (problem 1 1 "invalid hexadecimal escape"))
        (expect (read-back "(#\\xD800)") (problem 1 2 "invalid hexadecimal escape"))
        (expect (read-back " \"\\x110000;\"") (problem 1 2 "invalid hexadecimal escape")))

      ;; A token is a boolean, an integer that fits in I64, a float as
      ;; written, or a name; `.` and other `#` syntax are problems. A
      ;; no-break space is part of a token, and an Arabic-Indic digit is
      ;; no digit.
      (define (test-tokens)
        (expect (read-back "#t #true #f #false -7 +7 1.5 .5 1e9 - ... x->y")
                (Ok (list "#t" "#t" "#f" "#f" "-7" "7" "1.5" ".5" "1e9" "-" "..." "x->y")))
        (expect (read "t" "9223372036854775807 -9223372036854775808")
                (Ok (list (Atom (Integer 9223372036854775807) (Loc "t" 1 1))
                          (Atom (Integer -9223372036854775808) (Loc "t" 1 21)))))
        (expect (read "t" "a\xA0;b \x660;")
                (Ok (list (Ident "a\xA0;b" (Loc "t" 1 1)) (Ident "\x660;" (Loc "t" 1 5)))))
        (expect (read-back "(a . b)") (problem 1 4 "dotted lists are not part of Snail-Core"))
        (expect (read-back " #foo") (problem 1 2 "unsupported syntax #foo"))
        (expect (read-back "#u8[1]") (problem 1 1 "unsupported syntax #u8"))
        (expect (read-back "9223372036854775808")
                (problem 1 1 "the literal 9223372036854775808 does not fit I64")))

      ;; Atmosphere separates bytes; a byte's problem is at the byte, and
      ;; an unclosed byte vector's at its opening.
      (define (test-byte-vectors)
        (expect (read-back "#u8(0 137 255) #u8( ) #u8(1;c\n2 #;3 4 #|5|#)")
                (Ok (list "#u8(0 137 255)" "#u8()" "#u8(1 2 4)")))
        (expect (read "t" "#u8(7)")
                (Ok (list (Atom (ByteVector (list->vector (list 7))) (Loc "t" 1 1)))))
        (expect (read-back "#u8(1 256)") (problem 1 7 "a byte is an integer from 0 to 255"))
        (expect (read-back "#u8(1 a)") (problem 1 7 "a byte is an integer from 0 to 255"))
        (expect (read-back "#u8(1 (2))") (problem 1 7 "a byte is an integer from 0 to 255"))
        (expect (read-back "#u8(1 ])") (problem 1 7 "a byte is an integer from 0 to 255"))
        (expect (read-back "#u8(1 \"2\")") (problem 1 7 "a byte is an integer from 0 to 255"))
        (expect (read-back "(#u8(1 2") (problem 1 2 "unclosed byte vector"))
        (expect (read-back "#u8(1 #|") (problem 1 9 "unterminated block comment")))

      ;; A problem inside a list, a quotation or a datum comment stops the
      ;; reader at the problem.
      (define (test-problems-inside)
        (expect (read-back "(a\n (b \"\\q\"))") (problem 2 5 "unknown string escape"))
        (expect (read-back "'(a .)") (problem 1 5 "dotted lists are not part of Snail-Core"))
        (expect (read-back "#;(a #\\nope) b") (problem 1 6 "unknown character name nope"))
        (expect (read-back "(a #;(b c)") (problem 1 1 "unclosed list")))))
   (else)))
