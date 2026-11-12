;; The pass `read`: a file's text becomes its located forms, in the Syntax
;; language. The reader is a recursive descent over the file's
;; characters, held in a vector so that a position is an index. The
;; lexical rules say what starts at an index and where it ends, the
;; literal rules what a literal's text stands for, and the line table where
;; an index is; this library decides only how lexemes make data. Reading
;; stops at the first problem, so a failure holds one piece of feedback.
;;
;; The pass has a second entry, `read-generated`, for the bytes a
;; producer writes in place of a generated library's text: the one form
;; its recipe returned, in the encoding (snail shell syntax) writes, read
;; into the same language, the old `decode-syntax`'s format and messages.
(define-library (snail compiler read pass)
  (export
   read
   read-generated)
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

    ;; ---- Producers' outputs ----

    ;; Each form is a tag byte and its contents:
    ;;
    ;;   0 list     a count, then that many forms
    ;;   1 symbol   a text
    ;;   2 number   a text the reader reads as an integer or a float
    ;;   3 string   a text
    ;;   4 char     a scalar's code
    ;;   5 #f, 6 #t
    ;;   7 bytes    a count, then that many bytes as they are
    ;;
    ;; A count or a code is seven bits to a byte, low bits first, with the
    ;; high bit set on every byte but the last; a text is a count of
    ;; scalars, then each scalar's code. Nothing in the bytes says where a
    ;; form is, so every node is at `loc`, where the integrator places the
    ;; producer's output: its recipe's expression. Every problem is there
    ;; too, and decoding stops at the first.
    (: read-generated (impl (Fn Bytes Loc -> (Result Syntax (List Feedback)))))
    (define (read-generated bytes loc)
      (placed loc (whole-form bytes loc)))

    ;; What decoding a part of the bytes answers: the value and the index
    ;; just after it, or the problem.
    (type (Decoding T) (Result (Scanned T) String))

    ;; The bytes hold one form and nothing after it.
    (: whole-form (impl (Fn Bytes Loc -> (Result Syntax String))))
    (define (whole-form bytes loc)
      (result-let* ((form (decoded-form bytes 0 loc)))
        (if (= (::end form) (vector-length bytes))
            (Ok (::value form))
            (malformed "bytes follow the library"))))

    ;; The form whose tag is at `index`.
    (: decoded-form (impl (Fn Bytes I64 Loc -> (Decoding Syntax))))
    (define (decoded-form bytes index loc)
      (result-let* ((tag (byte-at bytes index)))
        (let ((next (+ index 1)))
          (cond ((= tag 0) (decoded-list bytes next loc))
                ((<= tag 3) (decoded-text-form bytes next tag loc))
                ((= tag 4) (decoded-character bytes next loc))
                ((= tag 5) (Ok (Scanned (Atom (Boolean #f) loc) next)))
                ((= tag 6) (Ok (Scanned (Atom (Boolean #t) loc) next)))
                ((= tag 7) (decoded-bytes bytes next loc))
                (else (malformed "an unknown tag"))))))

    ;; A list's items, after its count at `index`.
    (: decoded-list (impl (Fn Bytes I64 Loc -> (Decoding Syntax))))
    (define (decoded-list bytes index loc)
      (result-let* ((count (decoded-count bytes index)))
        (let loop ((left (::value count))
                   (index (::end count))
                   (items (Nil)))
          (if (= left 0)
              (Ok (Scanned (Form (reverse items) loc) index))
              (result-let* ((item (decoded-form bytes index loc)))
                (loop (- left 1) (::end item) (Cons (::value item) items)))))))

    ;; A symbol, a number or a string, as tags 1, 2 and 3 mark them, whose
    ;; text is at `index`.
    (: decoded-text-form (impl (Fn Bytes I64 I64 Loc -> (Decoding Syntax))))
    (define (decoded-text-form bytes index tag loc)
      (result-let* ((text (decoded-text bytes index))
                    (syntax (text-syntax tag (::value text) loc)))
        (Ok (Scanned syntax (::end text)))))

    (: text-syntax (impl (Fn I64 String Loc -> (Result Syntax String))))
    (define (text-syntax tag text loc)
      (cond ((= tag 1) (Ok (Ident text loc)))
            ((= tag 2)
             (result-let* ((datum (number-datum text)))
               (Ok (Atom datum loc))))
            (else (Ok (Atom (Text text) loc)))))

    ;; A number is the text of a token that reads as one: an integer that
    ;; fits in I64, or a float, which keeps its text.
    (: number-datum (impl (Fn String -> (Result Datum String))))
    (define (number-datum text)
      (match (number-kind text)
        ((IntegerToken)
         (result-let* ((integer (integer-value text)))
           (Ok (Integer integer))))
        ((FloatToken) (Ok (Float text)))
        (_ (malformed (string-append "the number " text " does not read as one")))))

    ;; A text: a count of scalars, then each scalar's code.
    (: decoded-text (impl (Fn Bytes I64 -> (Decoding String))))
    (define (decoded-text bytes index)
      (result-let* ((count (decoded-count bytes index)))
        (let loop ((left (::value count))
                   (index (::end count))
                   (chars (Nil)))
          (if (= left 0)
              (Ok (Scanned (list->string (reverse chars)) index))
              (result-let* ((code (decoded-count bytes index))
                            (char (scalar (::value code))))
                (loop (- left 1) (::end code) (Cons char chars)))))))

    (: decoded-character (impl (Fn Bytes I64 Loc -> (Decoding Syntax))))
    (define (decoded-character bytes index loc)
      (result-let* ((code (decoded-count bytes index))
                    (char (scalar (::value code))))
        (Ok (Scanned (Atom (Character char) loc) (::end code)))))

    ;; A byte vector is cut from the bytes as they are.
    (: decoded-bytes (impl (Fn Bytes I64 Loc -> (Decoding Syntax))))
    (define (decoded-bytes bytes index loc)
      (result-let* ((count (decoded-count bytes index)))
        (let ((start (::end count))
              (end (+ (::end count) (::value count))))
          (if (<= end (vector-length bytes))
              (Ok (Scanned (Atom (ByteVector (subvector bytes start end)) loc) end))
              (malformed "it ends early")))))

    ;; Seven bits to a byte, low bits first. Five bytes bound a count well
    ;; inside I64 on every host, so a sixth is a problem, not an overflow.
    (: decoded-count (impl (Fn Bytes I64 -> (Decoding I64))))
    (define (decoded-count bytes index)
      (let loop ((index index)
                 (value 0)
                 (scale 1))
        (result-let* ((byte (byte-at bytes index)))
          (cond ((< byte 128) (Ok (Scanned (+ value (* byte scale)) (+ index 1))))
                ((= scale 268435456) (malformed "a count is too large"))
                (else (loop (+ index 1) (+ value (* (- byte 128) scale)) (* scale 128)))))))

    (: byte-at (impl (Fn Bytes I64 -> (Result I64 String))))
    (define (byte-at bytes index)
      (if (< index (vector-length bytes))
          (Ok (i32->i64 (u8->i32 (vector-ref bytes index))))
          (malformed "it ends early")))

    (: scalar (impl (Fn I64 -> (Result Char String))))
    (define (scalar code)
      (if (scalar-code? code)
          (Ok (integer->char code))
          (malformed "a code is not a Unicode scalar")))

    (: malformed (All (T) (impl (Fn String -> (Result T String)))))
    (define (malformed problem)
      (Err (string-append "malformed generated syntax: " problem)))

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
        (test-problems-inside)
        (test-generated)
        (test-generated-problems))

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
        (expect (read-back "(a #;(b c)") (problem 1 1 "unclosed list")))

      ;; ---- Producers' outputs ----

      (define (bytes codes)
        (list->vector codes))

      (define recipe (Loc "recipe.sld" 3 4))

      ;; (f "λ" -7 1.5 #\a #t #u8(0 200)), with a two-byte code for λ, every
      ;; node at the recipe; and one of each other kind.
      (define (test-generated)
        (expect (read-generated
                 (bytes (list 0 7 1 1 102 3 1 187 7 2 2 45 55 2 3 49 46 53 4 97 6 7 2 0 200))
                 recipe)
                (Ok (Form (list (Ident "f" recipe)
                                (Atom (Text "λ") recipe)
                                (Atom (Integer -7) recipe)
                                (Atom (Float "1.5") recipe)
                                (Atom (Character #\a) recipe)
                                (Atom (Boolean #t) recipe)
                                (Atom (ByteVector (bytes (list 0 200))) recipe))
                          recipe)))
        (expect (read-generated (bytes (list 5)) recipe) (Ok (Atom (Boolean #f) recipe)))
        (expect (read-generated (bytes (list 0 0)) recipe) (Ok (Form (list) recipe)))
        (expect (read-generated (bytes (list 3 0)) recipe) (Ok (Atom (Text "") recipe)))
        (expect (read-generated (bytes (list 7 0)) recipe)
                (Ok (Atom (ByteVector (bytes (list))) recipe)))
        (expect (read-generated (bytes (list 2 2 43 53)) recipe) (Ok (Atom (Integer 5) recipe)))
        ;; A count of five bytes, 2^28 + 1 here, is as large as one gets.
        (expect (read-generated (bytes (list 4 129 128 128 128 1)) recipe)
                (fail recipe "malformed generated syntax: a code is not a Unicode scalar")))

      ;; Each of the old decoder's problems, at the recipe.
      (define (test-generated-problems)
        (define (malformed codes problem)
          (expect (read-generated (bytes codes) recipe)
                  (fail recipe (string-append "malformed generated syntax: " problem))))
        (malformed (list) "it ends early")
        (malformed (list 0 2 1 1 102) "it ends early")
        (malformed (list 7 3 1 2) "it ends early")
        (malformed (list 1 128) "it ends early")
        (malformed (list 5 5) "bytes follow the library")
        (malformed (list 8) "an unknown tag")
        (malformed (list 0 1 9) "an unknown tag")
        (malformed (list 1 128 128 128 128 128 1) "a count is too large")
        (malformed (list 4 128 176 3) "a code is not a Unicode scalar")
        (malformed (list 3 1 128 128 68) "a code is not a Unicode scalar")
        (malformed (list 2 1 120) "the number x does not read as one")
        (malformed (list 2 0) "the number  does not read as one")
        (malformed (list 2 1 45) "the number - does not read as one")
        (expect (read-generated (bytes (append (list 2 19)
                                               (map char->integer
                                                    (string->list "9223372036854775808"))))
                                recipe)
                (fail recipe "the literal 9223372036854775808 does not fit I64")))))
   (else)))
