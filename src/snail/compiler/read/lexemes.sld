;; The reader's lexical rules: what starts at an index of a file's
;; characters, and the index just after it. Atmosphere, which the reader
;; skips, is asked for first; anything else starts a lexeme. The rules
;; never fail: a string or block comment that the text ends inside runs to
;; the end and says it is not closed, so (snail shell highlight) can
;; classify text the reader rejects, and the reader can say why it rejects
;; it. Nothing here reads data: the items of a list, and the datum a `#;`
;; comments out, are the reader's to find.
(define-library (snail compiler read lexemes)
  (export
   Scanned
   Atmosphere
   Whitespace
   LineComment
   BlockComment
   DatumComment
   atmosphere-at
   Lexeme
   ListOpen
   ListClose
   QuoteMark
   BytesOpen
   StringLexeme
   CharacterLexeme
   TokenLexeme
   EndOfText
   lexeme-at
   token-end
   TokenKind
   BooleanToken
   IntegerToken
   FloatToken
   NameToken
   InvalidToken
   token-kind
   number-kind)
  (import
   (snail core base))
  (begin

    ;; ---- Scans ----

    ;; What was found at an index of the text, and the index just after it.
    (struct (Scanned T)
      ((value T)
       (end I64)))

    ;; ---- Characters ----

    (: at-end? (impl (Fn (Vector Char) I64 -> Bool)))
    (define (at-end? chars index)
      (>= index (vector-length chars)))

    ;; Past the end of the text, no character is there.
    (: char-is? (impl (Fn (Vector Char) I64 Char -> Bool)))
    (define (char-is? chars index char)
      (and (not (at-end? chars index)) (char=? (vector-ref chars index) char)))

    (: chars-are? (impl (Fn (Vector Char) I64 Char Char -> Bool)))
    (define (chars-are? chars index first second)
      (and (char-is? chars index first) (char-is? chars (+ index 1) second)))

    ;; A token stops at the end of the text, and before whitespace, a
    ;; bracket, a string, a line comment or a quote mark. `#|` and `#;`
    ;; inside a token are part of it.
    (: delimiter? (impl (Fn (Vector Char) I64 -> Bool)))
    (define (delimiter? chars index)
      (or (at-end? chars index) (delimiter-char? (vector-ref chars index))))

    (: delimiter-char? (impl (Fn Char -> Bool)))
    (define (delimiter-char? c)
      (or (char-whitespace? c)
          (char=? c #\()
          (char=? c #\))
          (char=? c #\[)
          (char=? c #\])
          (char=? c #\")
          (char=? c #\;)
          (char=? c #\')))

    ;; ---- Atmosphere ----

    ;; What the reader skips between data. `#;` comments out the datum
    ;; after it, which the reader reads in order to skip it.
    (enum Atmosphere
      (Whitespace)
      (LineComment)
      (BlockComment ((closed Bool)))
      (DatumComment))

    ;; The atmosphere at `index`, if any starts there.
    (: atmosphere-at (impl (Fn (Vector Char) I64 -> (Option (Scanned Atmosphere)))))
    (define (atmosphere-at chars index)
      (cond ((at-end? chars index) (None))
            ((char-whitespace? (vector-ref chars index))
             (Some (Scanned (Whitespace) (whitespace-end chars index))))
            ((char-is? chars index #\;) (Some (Scanned (LineComment) (line-end chars index))))
            ((chars-are? chars index #\# #\|) (Some (block-comment chars (+ index 2) 1)))
            ((chars-are? chars index #\# #\;) (Some (Scanned (DatumComment) (+ index 2))))
            (else (None))))

    (: whitespace-end (impl (Fn (Vector Char) I64 -> I64)))
    (define (whitespace-end chars index)
      (if (and (not (at-end? chars index)) (char-whitespace? (vector-ref chars index)))
          (whitespace-end chars (+ index 1))
          index))

    ;; A line comment stops before its newline.
    (: line-end (impl (Fn (Vector Char) I64 -> I64)))
    (define (line-end chars index)
      (if (or (at-end? chars index) (char-is? chars index #\newline))
          index
          (line-end chars (+ index 1))))

    ;; Block comments nest: `depth` counts the ones open at `index`.
    (: block-comment (impl (Fn (Vector Char) I64 I64 -> (Scanned Atmosphere))))
    (define (block-comment chars index depth)
      (cond ((= depth 0) (Scanned (BlockComment #t) index))
            ((at-end? chars index) (Scanned (BlockComment #f) index))
            ((chars-are? chars index #\| #\#) (block-comment chars (+ index 2) (- depth 1)))
            ((chars-are? chars index #\# #\|) (block-comment chars (+ index 2) (+ depth 1)))
            (else (block-comment chars (+ index 1) depth))))

    ;; ---- Lexemes ----

    ;; What starts a datum. A list closes with the bracket that opened it.
    ;; A token is any other text up to a delimiter; `token-kind` says what
    ;; it is.
    (enum Lexeme
      (ListOpen ((close Char)))
      (ListClose ((close Char)))
      (QuoteMark)
      (BytesOpen)
      (StringLexeme ((closed Bool)))
      (CharacterLexeme)
      (TokenLexeme)
      (EndOfText))

    ;; The lexeme at `index`, where no atmosphere starts.
    (: lexeme-at (impl (Fn (Vector Char) I64 -> (Scanned Lexeme))))
    (define (lexeme-at chars index)
      (if (at-end? chars index)
          (Scanned (EndOfText) index)
          (lexeme-from chars index (vector-ref chars index))))

    ;; The lexeme that `c`, the character at `index`, starts.
    (: lexeme-from (impl (Fn (Vector Char) I64 Char -> (Scanned Lexeme))))
    (define (lexeme-from chars index c)
      (let ((next (+ index 1)))
        (cond ((char=? c #\() (Scanned (ListOpen #\)) next))
              ((char=? c #\[) (Scanned (ListOpen #\]) next))
              ((or (char=? c #\)) (char=? c #\])) (Scanned (ListClose c) next))
              ((char=? c #\") (string-lexeme chars next))
              ((char=? c #\') (Scanned (QuoteMark) next))
              ((chars-are? chars index #\# #\\)
               (Scanned (CharacterLexeme) (character-end chars (+ index 2))))
              ((bytes-opening? chars index) (Scanned (BytesOpen) (+ index 4)))
              (else (Scanned (TokenLexeme) (token-end chars index))))))

    ;; A string runs to the first quote that a backslash does not escape. A
    ;; backslash takes the character after it, if the text has one.
    (: string-lexeme (impl (Fn (Vector Char) I64 -> (Scanned Lexeme))))
    (define (string-lexeme chars index)
      (cond ((at-end? chars index) (Scanned (StringLexeme #f) index))
            ((char-is? chars index #\") (Scanned (StringLexeme #t) (+ index 1)))
            ((char-is? chars index #\\)
             (string-lexeme chars (min (+ index 2) (vector-length chars))))
            (else (string-lexeme chars (+ index 1)))))

    ;; `#\` takes the character after it, whatever it is, so `#\(` and `#\ `
    ;; are characters; a name runs on to a delimiter, as in `#\space`.
    (: character-end (impl (Fn (Vector Char) I64 -> I64)))
    (define (character-end chars index)
      (if (at-end? chars index) index (token-end chars (+ index 1))))

    ;; `#u8(` opens a byte vector, as in R7RS.
    (: bytes-opening? (impl (Fn (Vector Char) I64 -> Bool)))
    (define (bytes-opening? chars index)
      (and (chars-are? chars index #\# #\u) (chars-are? chars (+ index 2) #\8 #\()))

    ;; The first delimiter at or after `index`.
    (: token-end (impl (Fn (Vector Char) I64 -> I64)))
    (define (token-end chars index)
      (if (delimiter? chars index) index (token-end chars (+ index 1))))

    ;; ---- Tokens ----

    ;; What the reader makes of a token's text.
    (enum TokenKind
      (BooleanToken ((value Bool)))
      (IntegerToken)
      (FloatToken)
      (NameToken)
      (InvalidToken ((problem String))))

    ;; The kind of a token, whose text is never empty: a lexeme starts with
    ;; a character that is no delimiter.
    (: token-kind (impl (Fn String -> TokenKind)))
    (define (token-kind text)
      (cond ((or (string=? text "#t") (string=? text "#true")) (BooleanToken #t))
            ((or (string=? text "#f") (string=? text "#false")) (BooleanToken #f))
            ((string=? text ".") (InvalidToken "dotted lists are not part of Snail-Core"))
            ((char=? (string-ref text 0) #\#)
             (InvalidToken (string-append "unsupported syntax " text)))
            (else (number-kind text))))

    ;; ---- Numbers ----

    ;; An optionally signed decimal integer, or a decimal float with a point
    ;; or an exponent. Any other text is a name, as `-`, `...`, `1+` and
    ;; the empty text are. A producer's number is read by this alone.
    (: number-kind (impl (Fn String -> TokenKind)))
    (define (number-kind text)
      (let ((magnitude (unsigned text)))
        (cond ((not (number-start? magnitude)) (NameToken))
              ((digits? magnitude) (IntegerToken))
              ((float-text? magnitude) (FloatToken))
              (else (NameToken)))))

    ;; `text` without the sign it may start with.
    (: unsigned (impl (Fn String -> String)))
    (define (unsigned text)
      (if (and (> (string-length text) 0) (sign? (string-ref text 0)))
          (substring text 1 (string-length text))
          text))

    (: sign? (impl (Fn Char -> Bool)))
    (define (sign? c)
      (or (char=? c #\-) (char=? c #\+)))

    ;; A number starts with a digit or a point.
    (: number-start? (impl (Fn String -> Bool)))
    (define (number-start? text)
      (and (> (string-length text) 0)
           (or (char-numeric? (string-ref text 0)) (char=? (string-ref text 0) #\.))))

    ;; One or more decimal digits.
    (: digits? (impl (Fn String -> Bool)))
    (define (digits? text)
      (and (> (string-length text) 0) (every? char-numeric? (string->list text))))

    ;; A mantissa with a point, or a mantissa, an `e` or `E`, and an
    ;; optionally signed exponent: `1.5`, `.5`, `1.`, `1e9`, `2.5E-3`.
    (: float-text? (impl (Fn String -> Bool)))
    (define (float-text? text)
      (match (list-index exponent-mark? (string->list text))
        ((Some mark)
         (and (mantissa? (substring text 0 mark))
              (digits? (unsigned (substring text (+ mark 1) (string-length text))))))
        ((None) (and (mantissa? text) (point? text)))))

    (: exponent-mark? (impl (Fn Char -> Bool)))
    (define (exponent-mark? c)
      (or (char=? c #\e) (char=? c #\E)))

    ;; Digits with at most one point among them, and at least one digit.
    (: mantissa? (impl (Fn String -> Bool)))
    (define (mantissa? text)
      (let ((chars (string->list text)))
        (and (any? char-numeric? chars)
             (every? (lambda (c) (or (char-numeric? c) (char=? c #\.))) chars)
             (<= (length (filter (lambda (c) (char=? c #\.)) chars)) 1))))

    (: point? (impl (Fn String -> Bool)))
    (define (point? text)
      (match (string-index text #\.)
        ((Some _) #t)
        ((None) #f)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-lexemes)
    (import
     (snail stage0 testing))
    (begin
      (define (test-lexemes)
        (test-atmosphere)
        (test-block-comments)
        (test-brackets-and-marks)
        (test-strings)
        (test-characters)
        (test-tokens)
        (test-token-kinds)
        (test-numbers)
        (test-ascii-classes))

      ;; The atmosphere at index 0 of `text`.
      (define (atmosphere text)
        (atmosphere-at (string->vector text) 0))

      ;; The lexeme at index 0 of `text`.
      (define (lexeme text)
        (lexeme-at (string->vector text) 0))

      (define (test-atmosphere)
        (expect (atmosphere " \t\n x") (Some (Scanned (Whitespace) 4)))
        (expect (atmosphere "; a note\nx") (Some (Scanned (LineComment) 8)))
        (expect (atmosphere "; to the end") (Some (Scanned (LineComment) 12)))
        (expect (atmosphere "#;(a b)") (Some (Scanned (DatumComment) 2)))
        (expect (atmosphere "x ") (None))
        (expect (atmosphere "#t") (None))
        (expect (atmosphere "") (None))
        (expect (atmosphere-at (string->vector "a ") 1) (Some (Scanned (Whitespace) 2)))
        (expect (atmosphere-at (string->vector "a ") 2) (None)))

      ;; A block comment closes when every one opened inside it has; one
      ;; the text ends inside runs to the end.
      (define (test-block-comments)
        (expect (atmosphere "#| a |# x") (Some (Scanned (BlockComment #t) 7)))
        (expect (atmosphere "#| #| |# |# x") (Some (Scanned (BlockComment #t) 11)))
        (expect (atmosphere "#|# |#") (Some (Scanned (BlockComment #t) 6)))
        (expect (atmosphere "#| #| |#") (Some (Scanned (BlockComment #f) 8)))
        (expect (atmosphere "#|") (Some (Scanned (BlockComment #f) 2))))

      (define (test-brackets-and-marks)
        (expect (lexeme "(a)") (Scanned (ListOpen #\)) 1))
        (expect (lexeme "[a]") (Scanned (ListOpen #\]) 1))
        (expect (lexeme ")") (Scanned (ListClose #\)) 1))
        (expect (lexeme "]") (Scanned (ListClose #\]) 1))
        (expect (lexeme "'a") (Scanned (QuoteMark) 1))
        (expect (lexeme "#u8(1)") (Scanned (BytesOpen) 4))
        (expect (lexeme "") (Scanned (EndOfText) 0))
        (expect (lexeme-at (string->vector "ab") 2) (Scanned (EndOfText) 2)))

      ;; A backslash takes the character after it, even a quote, and a
      ;; string the text ends inside runs to the end.
      (define (test-strings)
        (expect (lexeme "\"ab\" c") (Scanned (StringLexeme #t) 4))
        (expect (lexeme "\"a\\\"b\"") (Scanned (StringLexeme #t) 6))
        (expect (lexeme "\"a\\\\\"") (Scanned (StringLexeme #t) 5))
        (expect (lexeme "\"ab") (Scanned (StringLexeme #f) 3))
        (expect (lexeme "\"a\\") (Scanned (StringLexeme #f) 3))
        (expect (lexeme "\"a\\\"") (Scanned (StringLexeme #f) 4)))

      (define (test-characters)
        (expect (lexeme "#\\a b") (Scanned (CharacterLexeme) 3))
        (expect (lexeme "#\\space)") (Scanned (CharacterLexeme) 7))
        (expect (lexeme "#\\(") (Scanned (CharacterLexeme) 3))
        (expect (lexeme "#\\ ") (Scanned (CharacterLexeme) 3))
        (expect (lexeme "#\\") (Scanned (CharacterLexeme) 2)))

      ;; A token runs to a delimiter; `#u8` without its parenthesis and
      ;; `#` alone are tokens too.
      (define (test-tokens)
        (expect (lexeme "abc def") (Scanned (TokenLexeme) 3))
        (expect (lexeme "a(b") (Scanned (TokenLexeme) 1))
        (expect (lexeme "a\"b\"") (Scanned (TokenLexeme) 1))
        (expect (lexeme "a;b") (Scanned (TokenLexeme) 1))
        (expect (lexeme "a'b") (Scanned (TokenLexeme) 1))
        (expect (lexeme "a#|b|#") (Scanned (TokenLexeme) 6))
        (expect (lexeme "#u8[1]") (Scanned (TokenLexeme) 3))
        (expect (lexeme "#") (Scanned (TokenLexeme) 1))
        (expect (token-end (string->vector "12 3") 0) 2)
        (expect (token-end (string->vector "12)") 0) 2)
        (expect (token-end (string->vector ")") 0) 0)
        (expect (token-end (string->vector "12") 2) 2))

      (define (test-token-kinds)
        (expect (token-kind "#t") (BooleanToken #t))
        (expect (token-kind "#true") (BooleanToken #t))
        (expect (token-kind "#f") (BooleanToken #f))
        (expect (token-kind "#false") (BooleanToken #f))
        (expect (token-kind ".") (InvalidToken "dotted lists are not part of Snail-Core"))
        (expect (token-kind "#u8") (InvalidToken "unsupported syntax #u8"))
        (expect (token-kind "#") (InvalidToken "unsupported syntax #"))
        (expect (token-kind "define") (NameToken))
        (expect (token-kind "λ") (NameToken)))

      (define (test-numbers)
        (expect-kind (IntegerToken) (list "0" "42" "-7" "+7" "007"))
        (expect-kind (FloatToken) (list "1.5" ".5" "1." "-.5" "1e9" "1E9" "2.5e-3" "1e+3"))
        (expect-kind (NameToken) (list "-" "+" "..." "1+" "1.2.3" "1e" "1e-" "e5" "1x" ".e5" "-a"))
        (expect (number-kind "") (NameToken))
        (expect (number-kind "#t") (NameToken)))

      ;; The character classes are ASCII's on both hosts. Only space, tab,
      ;; newline and return are whitespace, so a no-break space (U+00A0),
      ;; an ideographic space (U+3000) or a form feed is token text; only 0
      ;; to 9 are digits, so an Arabic-Indic zero (U+0660) makes a name.
      (define (test-ascii-classes)
        (expect (atmosphere " \t\r\n") (Some (Scanned (Whitespace) 4)))
        (expect (atmosphere "\xA0;a") (None))
        (expect (atmosphere "\x3000;a") (None))
        (expect (lexeme "a\xA0;b c") (Scanned (TokenLexeme) 3))
        (expect (lexeme "\x3000; x") (Scanned (TokenLexeme) 1))
        (expect (lexeme "a\x0C;b") (Scanned (TokenLexeme) 3))
        (expect-kind (NameToken) (list "\x660;" "1\x660;" "-\x660;" "\x660;.5")))

      ;; Each of `texts` is a token of `kind`. The text is part of what is
      ;; compared, so a failure names it.
      (define (expect-kind kind texts)
        (for-each (lambda (text) (expect (Pair text (token-kind text)) (Pair text kind))) texts))))
   (else)))
