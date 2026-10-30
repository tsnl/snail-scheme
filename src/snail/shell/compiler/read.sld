;; Text to located syntax. The reader is a recursive descent over a vector
;; of characters; a position is just an index, and line and column are
;; recovered from a table of line starts only when a location is needed.
;; Its lexical rules, the "Lexemes" section, are exported, and
;; (snail shell highlight) classifies text with them. The syntax a
;; `generate-library` producer writes arrives as bytes instead, and is
;; decoded without passing through text. Every pass reads locations from
;; here, so the "Source failures" section also declares how any pass stops
;; a compile: the `compile` effect.
(define-library (snail shell compiler read)
  (export
   Loc
   Loc-file
   Loc-line
   Loc-column
   loc->string
   Datum
   DInt
   DFloat
   DString
   DChar
   DBytes
   DBool
   DUnit
   Syntax
   Atom
   Ident
   Ident-name
   Ident-mark
   Ident-loc
   Form
   Form-items
   Form-loc
   Mark
   Mark-key
   Mark-original
   Mark-scope
   syntax-loc
   datum=?
   bytes=?
   datum->string
   syntax->string
   compile-error
   SourceDiagnostic
   SourceDiagnostic-loc
   SourceDiagnostic-message
   diagnostic->string
   CompilerRequest
   GenerateInput
   ArtifactInput
   compile
   fail
   need
   Stop
   Failed
   Requested
   compiling
   read-text
   decode-syntax
   Source
   make-source
   source-text
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
   TokenKind
   BooleanToken
   IntegerToken
   FloatToken
   NameToken
   InvalidToken
   token-kind)
  (import
   (snail core base))
  (begin

    ;; ---- Locations and syntax ----

    (struct Loc
      ((file String)
       (line I64)
       (column I64)))

    ;; A literal. A float keeps its text, which only the backend interprets.
    (enum Datum
      (DInt ((value I64)))
      (DFloat ((text String)))
      (DString ((value String)))
      (DChar ((value Char)))
      (DBytes ((value Bytes)))
      (DBool ((value Bool)))
      (DUnit))

    ;; An identifier a macro template introduces carries a mark: a key unique
    ;; to the expansion, the template's identifier, and the number of the
    ;; macro's definition scope, which the expander resolves.
    (enum Syntax
      (Atom ((value Datum) (loc Loc)))
      (Ident ((name String) (mark (Option Mark)) (loc Loc)))
      (Form ((items (List Syntax)) (loc Loc))))

    (struct Mark
      ((key String)
       (original Syntax)
       (scope I64)))

    (: syntax-loc (-> Syntax Loc))
    (define (syntax-loc syntax)
      (match syntax
        ((Atom _ loc) loc)
        ((Ident _ _ loc) loc)
        ((Form _ loc) loc)))

    ;; Syntax as source text, for diagnostics and tests.
    (: syntax->string (-> Syntax String))
    (define (syntax->string syntax)
      (match syntax
        ((Atom value _) (datum->string value))
        ((Ident name _ _) name)
        ((Form items _) (string-append "(" (string-join (map syntax->string items) " ") ")"))))

    (: datum->string (-> Datum String))
    (define (datum->string datum)
      (match datum
        ((DInt value) (i64->string value))
        ((DFloat text) text)
        ((DString value) (string-literal value))
        ((DChar value) (string-append "#\\" (list->string (list value))))
        ((DBytes value)
         (string-append "#u8("
                        (string-join (map (lambda (byte) (i64->string (i32->i64 (u8->i32 byte))))
                                          (vector->list value))
                                     " ")
                        ")"))
        ((DBool value) (if value "#t" "#f"))
        ((DUnit) "(unit)")))

    ;; A string as a literal the reader reads back.
    (: string-literal (-> String String))
    (define (string-literal text)
      (string-append
       "\""
       (string-concatenate
        (map (lambda (c)
               (cond ((char=? c #\") "\\\"")
                     ((char=? c #\\) "\\\\")
                     ((char=? c #\newline) "\\n")
                     (else (list->string (list c)))))
             (string->list text)))
       "\""))

    (: datum=? (-> Datum Datum Bool))
    (define (datum=? a b)
      (match a
        ((DInt x) (match b ((DInt y) (= x y)) (_ #f)))
        ((DFloat x) (match b ((DFloat y) (string=? x y)) (_ #f)))
        ((DString x) (match b ((DString y) (string=? x y)) (_ #f)))
        ((DChar x) (match b ((DChar y) (char=? x y)) (_ #f)))
        ((DBytes x) (match b ((DBytes y) (bytes=? x y)) (_ #f)))
        ((DBool x) (match b ((DBool y) (eq-bool? x y)) (_ #f)))
        ((DUnit) (match b ((DUnit) #t) (_ #f)))))

    (: bytes=? (-> Bytes Bytes Bool))
    (define (bytes=? a b)
      (and (= (vector-length a) (vector-length b))
           (let loop ((index 0))
             (or (= index (vector-length a))
                 (and (= (u8->i32 (vector-ref a index)) (u8->i32 (vector-ref b index)))
                      (loop (+ index 1)))))))

    (: eq-bool? (-> Bool Bool Bool))
    (define (eq-bool? a b)
      (if a b (not b)))

    (: loc->string (-> Loc String))
    ;; A location in line 0 is the file as a whole.
    (define (loc->string loc)
      (if (= (Loc-line loc) 0)
          (Loc-file loc)
          (string-append (Loc-file loc)
                         ":"
                         (i64->string (Loc-line loc))
                         ":"
                         (i64->string (Loc-column loc)))))

    ;; ---- Source failures ----

    (struct SourceDiagnostic
      ((loc Loc)
       (message String)))

    ;; A diagnostic as a person reads it: where, then what.
    (: diagnostic->string (-> SourceDiagnostic String))
    (define (diagnostic->string diagnostic)
      (string-append (loc->string (SourceDiagnostic-loc diagnostic))
                     ": "
                     (SourceDiagnostic-message diagnostic)))

    ;; Every pass reports a source error by performing the compile effect's
    ;; `fail`. Nothing after the call runs: the entry point's handler takes
    ;; the diagnostic and hands it to its caller.
    (: compile-error (All (A) (-> Loc String A ! compile)))
    (define (compile-error loc message)
      (absurd (fail (SourceDiagnostic loc message))))

    ;; What a compile asks its caller for when it was not supplied it: the
    ;; output of the producer printed under `key`, or a project target's
    ;; files, for the `artifact-files` use at `source`.
    (enum CompilerRequest
      (GenerateInput ((key String)))
      (ArtifactInput
       ((name String)
        (source Loc))))

    ;; A compile stops, short of its result, when the source is wrong or
    ;; when it needs an input it was not supplied. Neither operation returns
    ;; to the pass that performs it, so a yield to this effect saves no
    ;; frames, and each entry point handles it with `compiling`, which
    ;; turns the compile into a Result.
    (effect compile
      ((ctl fail (-> SourceDiagnostic Never))
       (ctl need (-> CompilerRequest Never))))

    (enum Stop
      (Failed ((diagnostic SourceDiagnostic)))
      (Requested ((request CompilerRequest))))

    (: compiling (All (T e) (-> (-> T ! compile e) (Result T Stop) ! e)))
    (define (compiling work)
      (handle compile
          ((fail (lambda (diagnostic) (Err (Failed diagnostic))))
           (need (lambda (request) (Err (Requested request)))))
        (Ok (work))))

    ;; ---- Line table ----

    (struct Source
      ((file String)
       (chars (Vector Char))
       (line-starts (Vector I64))))

    (: make-source (-> String String Source))
    (define (make-source file text)
      (let ((chars (string->vector text)))
        (let loop ((index 0) (starts (list 0)))
          (cond
           ((= index (vector-length chars)) (Source file chars (list->vector (reverse starts))))
           ((char=? (vector-ref chars index) #\newline)
            (loop (+ index 1) (Cons (+ index 1) starts)))
           (else (loop (+ index 1) starts))))))

    (: source-text (-> Source I64 I64 String))
    (define (source-text source start end)
      (vector->string (subvector (Source-chars source) start end)))

    ;; Binary search for the last line that starts at or before `index`.
    (: source-loc (-> Source I64 Loc))
    (define (source-loc source index)
      (let ((starts (Source-line-starts source)))
        (let search ((low 0) (high (- (vector-length starts) 1)))
          (if (= low high)
              (Loc (Source-file source) (+ low 1) (+ (- index (vector-ref starts low)) 1))
              (let ((middle (quotient (+ (+ low high) 1) 2)))
                (if (<= (vector-ref starts middle) index)
                    (search middle high)
                    (search low (- middle 1))))))))

    ;; ---- Characters ----

    ;; The character at `index`, or NUL past the end; scans test `at-end?`
    ;; before they act on a NUL.
    (: peek (-> Source I64 Char))
    (define (peek source index)
      (let ((chars (Source-chars source)))
        (if (< index (vector-length chars)) (vector-ref chars index) (integer->char 0))))

    (: char-is? (-> Source I64 Char Bool))
    (define (char-is? source index char)
      (and (not (at-end? source index)) (char=? (peek source index) char)))

    (: at-end? (-> Source I64 Bool))
    (define (at-end? source index)
      (>= index (vector-length (Source-chars source))))

    (: delimiter? (-> Source I64 Bool))
    (define (delimiter? source index)
      (let ((c (peek source index)))
        (or (at-end? source index)
            (char-whitespace? c)
            (char=? c #\()
            (char=? c #\))
            (char=? c #\[)
            (char=? c #\])
            (char=? c #\") (char=? c #\;) (char=? c #\'))))

    ;; ---- Lexemes ----

    ;; The reader's lexical rules: what starts at an index, and the index
    ;; after it. (snail shell highlight) classifies text with these same
    ;; functions, so highlighting cannot disagree with reading. Atmosphere,
    ;; which the reader skips, is asked for first; anything else starts a
    ;; datum. Scanning never fails: a string or block comment that the text
    ;; ends inside runs to the end and says it is not closed, so a highlighter
    ;; can classify text the reader rejects, and the reader says why.

    ;; What the reader skips between data. `#;` comments out the datum after
    ;; it, which the reader reads in order to skip it.
    (enum Atmosphere
      (Whitespace)
      (LineComment)
      (BlockComment ((closed Bool)))
      (DatumComment))

    ;; What starts a datum. A list closes with the bracket that opened it. A
    ;; token is any other text up to a delimiter; `token-kind` says what it is.
    (enum Lexeme
      (ListOpen ((close Char)))
      (ListClose ((close Char)))
      (QuoteMark)
      (BytesOpen)
      (StringLexeme ((closed Bool)))
      (CharacterLexeme)
      (TokenLexeme)
      (EndOfText))

    ;; The atmosphere at `index` and the index after it, if any starts there.
    (: atmosphere-at (-> Source I64 (Option (Pair Atmosphere I64))))
    (define (atmosphere-at source index)
      (let ((c (peek source index)))
        (cond ((at-end? source index) (None))
              ((char-whitespace? c) (Some (Pair (Whitespace) (whitespace-end source index))))
              ((char=? c #\;) (Some (Pair (LineComment) (line-end source index))))
              ((and (char=? c #\#) (char-is? source (+ index 1) #\|))
               (Some (block-comment source (+ index 2) 1)))
              ((and (char=? c #\#) (char-is? source (+ index 1) #\;))
               (Some (Pair (DatumComment) (+ index 2))))
              (else (None)))))

    (: whitespace-end (-> Source I64 I64))
    (define (whitespace-end source index)
      (if (and (not (at-end? source index)) (char-whitespace? (peek source index)))
          (whitespace-end source (+ index 1))
          index))

    ;; A line comment stops before its newline.
    (: line-end (-> Source I64 I64))
    (define (line-end source index)
      (if (or (at-end? source index) (char-is? source index #\newline))
          index
          (line-end source (+ index 1))))

    ;; Block comments nest.
    (: block-comment (-> Source I64 I64 (Pair Atmosphere I64)))
    (define (block-comment source index depth)
      (cond ((= depth 0) (Pair (BlockComment #t) index))
            ((at-end? source index) (Pair (BlockComment #f) index))
            ((and (char-is? source index #\|) (char-is? source (+ index 1) #\#))
             (block-comment source (+ index 2) (- depth 1)))
            ((and (char-is? source index #\#) (char-is? source (+ index 1) #\|))
             (block-comment source (+ index 2) (+ depth 1)))
            (else (block-comment source (+ index 1) depth))))

    ;; The lexeme at `index`, where no atmosphere starts, and the index after
    ;; it.
    (: lexeme-at (-> Source I64 (Pair Lexeme I64)))
    (define (lexeme-at source index)
      (let ((c (peek source index)) (next (+ index 1)))
        (cond ((at-end? source index) (Pair (EndOfText) index))
              ((char=? c #\() (Pair (ListOpen #\)) next))
              ((char=? c #\[) (Pair (ListOpen #\]) next))
              ((or (char=? c #\)) (char=? c #\])) (Pair (ListClose c) next))
              ((char=? c #\") (string-lexeme source next))
              ((char=? c #\') (Pair (QuoteMark) next))
              ((and (char=? c #\#) (char-is? source next #\\))
               (Pair (CharacterLexeme) (character-end source (+ index 2))))
              ((bytes-opening? source index) (Pair (BytesOpen) (+ index 4)))
              (else (Pair (TokenLexeme) (token-end source index))))))

    ;; A string runs to the first quote that a backslash does not escape.
    (: string-lexeme (-> Source I64 (Pair Lexeme I64)))
    (define (string-lexeme source index)
      (cond ((at-end? source index) (Pair (StringLexeme #f) index))
            ((char-is? source index #\") (Pair (StringLexeme #t) (+ index 1)))
            ((char-is? source index #\\)
             (string-lexeme source (min (+ index 2) (vector-length (Source-chars source)))))
            (else (string-lexeme source (+ index 1)))))

    ;; `#\` takes the character after it, whatever it is, so `#\(` and `#\ `
    ;; are characters; a name runs on to a delimiter, as in `#\space`.
    (: character-end (-> Source I64 I64))
    (define (character-end source index)
      (if (at-end? source index) index (token-end source (+ index 1))))

    ;; `#u8(` opens a byte vector, as in R7RS.
    (: bytes-opening? (-> Source I64 Bool))
    (define (bytes-opening? source index)
      (and (char-is? source index #\#)
           (char-is? source (+ index 1) #\u)
           (char-is? source (+ index 2) #\8)
           (char-is? source (+ index 3) #\()))

    (: token-end (-> Source I64 I64))
    (define (token-end source index)
      (if (delimiter? source index) index (token-end source (+ index 1))))

    ;; ---- Data ----

    ;; Skips whitespace, comments, and the data that `#;` comments out.
    (: skip-atmosphere (-> Source I64 I64 ! compile))
    (define (skip-atmosphere source index)
      (match (atmosphere-at source index)
        ((Some (Pair (BlockComment #f) end))
         (compile-error (source-loc source end) "unterminated block comment"))
        ((Some (Pair (DatumComment) end))
         (skip-atmosphere source (Pair-second (read-datum source end))))
        ((Some (Pair _ end)) (skip-atmosphere source end))
        ((None) index)))

    ;; The datum starting at `index`, and the index after it.
    (: read-datum (-> Source I64 (Pair Syntax I64) ! compile))
    (define (read-datum source index)
      (let ((start (skip-atmosphere source index)))
        (read-lexeme source start (lexeme-at source start))))

    ;; The datum that the lexeme at `start` begins, and the index after it.
    (: read-lexeme (-> Source I64 (Pair Lexeme I64) (Pair Syntax I64) ! compile))
    (define (read-lexeme source start lexeme)
      (let ((loc (source-loc source start)) (end (Pair-second lexeme)))
        (match (Pair-first lexeme)
          ((EndOfText) (compile-error loc "expected a datum before the end of the file"))
          ((ListOpen close) (read-list source end close loc (Nil)))
          ((ListClose _) (compile-error loc "unexpected closing parenthesis"))
          ((StringLexeme closed)
           (if closed
               (Pair (Atom (DString (string-value source (+ start 1) (- end 1) loc)) loc) end)
               (compile-error loc "unterminated string")))
          ((QuoteMark) (read-quote source end loc))
          ((CharacterLexeme)
           (Pair (Atom (DChar (character-value source (+ start 2) end loc)) loc) end))
          ((BytesOpen) (read-bytes source end loc (Nil)))
          ((TokenLexeme) (Pair (token-syntax (source-text source start end) loc) end)))))

    ;; The bytes of `#u8(...)`, each an integer from 0 to 255. Images make
    ;; literals of millions of bytes, so they gather a chunk at a time into
    ;; packed vectors, which are joined at the closing parenthesis.
    (: read-bytes (-> Source I64 Loc (List Bytes) (Pair Syntax I64) ! compile))
    (define (read-bytes source index loc chunks)
      (let* ((chunk (read-byte-chunk source index loc))
             (bytes (Pair-first chunk))
             (next (Pair-second chunk)))
        (if (< (vector-length bytes) byte-chunk)
            (Pair (Atom (DBytes (vector-concatenate (reverse (Cons bytes chunks)))) loc) next)
            (read-bytes source next loc (Cons bytes chunks)))))

    (define byte-chunk 4096)

    ;; Up to `byte-chunk` bytes, and the index after them: past the closing
    ;; parenthesis when fewer remain.
    (: read-byte-chunk (-> Source I64 Loc (Pair Bytes I64) ! compile))
    (define (read-byte-chunk source index loc)
      (let loop ((index index) (bytes (Nil)) (count 0))
        (let ((start (skip-atmosphere source index)))
          (cond ((= count byte-chunk) (Pair (list->vector (reverse bytes)) start))
                ((at-end? source start) (compile-error loc "unclosed byte vector"))
                ((char-is? source start #\)) (Pair (list->vector (reverse bytes)) (+ start 1)))
                (else (let ((end (token-end source start)))
                        (loop end (Cons (byte-token source start end) bytes) (+ count 1))))))))

    (: byte-token (-> Source I64 I64 U8 ! compile))
    (define (byte-token source start end)
      (let loop ((index start) (value 0))
        (cond ((and (= index end) (< start end) (<= value 255)) (i32->u8 (i64->i32 value)))
              ((or (= index end)
                   (> value 255)
                   (not (char-numeric? (vector-ref (Source-chars source) index))))
               (compile-error (source-loc source start) "a byte is an integer from 0 to 255"))
              (else (loop (+ index 1)
                          (+ (* value 10)
                             (digit-value (vector-ref (Source-chars source) index))))))))

    (: read-quote (-> Source I64 Loc (Pair Syntax I64) ! compile))
    (define (read-quote source index loc)
      (let ((quoted (read-datum source index)))
        (Pair (Form (list (Ident "quote" (None) loc) (Pair-first quoted)) loc)
              (Pair-second quoted))))

    (: read-list (-> Source I64 Char Loc (List Syntax) (Pair Syntax I64) ! compile))
    (define (read-list source index close loc items)
      (let* ((start (skip-atmosphere source index)) (lexeme (lexeme-at source start)))
        (match (Pair-first lexeme)
          ((EndOfText) (compile-error loc "unclosed list"))
          ((ListClose c)
           (if (char=? c close)
               (Pair (Form (reverse items) loc) (Pair-second lexeme))
               (compile-error (source-loc source start) "mismatched closing parenthesis")))
          (_ (let ((item (read-lexeme source start lexeme)))
               (read-list source (Pair-second item) close loc (Cons (Pair-first item) items)))))))

    ;; ---- Strings and characters ----

    ;; The text of a string whose characters run from `start` to its closing
    ;; quote at `close`. A backslash there always has a character after it,
    ;; which the string's lexeme skipped.
    (: string-value (-> Source I64 I64 Loc String ! compile))
    (define (string-value source start close loc)
      (let loop ((index start) (chars (Nil)))
        (cond ((= index close) (list->string (reverse chars)))
              ((char-is? source index #\\)
               (let ((escaped (read-escape source (+ index 1) close loc)))
                 (loop (Pair-second escaped) (Cons (Pair-first escaped) chars))))
              (else (loop (+ index 1) (Cons (peek source index) chars))))))

    (: read-escape (-> Source I64 I64 Loc (Pair Char I64) ! compile))
    (define (read-escape source index close loc)
      (let ((c (peek source index)))
        (cond ((char=? c #\n) (Pair #\newline (+ index 1)))
              ((char=? c #\t) (Pair #\tab (+ index 1)))
              ((char=? c #\r) (Pair (integer->char 13) (+ index 1)))
              ((char=? c #\0) (Pair (integer->char 0) (+ index 1)))
              ((char=? c #\x) (hex-escape source (+ index 1) close loc))
              ((or (char=? c #\\) (char=? c #\") (char=? c #\|)) (Pair c (+ index 1)))
              (else (compile-error loc "unknown string escape")))))

    ;; `\x41;`: hexadecimal digits and a semicolon, inside the string.
    (: hex-escape (-> Source I64 I64 Loc (Pair Char I64) ! compile))
    (define (hex-escape source index close loc)
      (let ((end (scan-until source index close #\;)))
        (if (= end close)
            (compile-error loc "invalid hexadecimal escape")
            (Pair (hex-char source index end loc) (+ end 1)))))

    (: scan-until (-> Source I64 I64 Char I64))
    (define (scan-until source index end stop)
      (if (or (= index end) (char-is? source index stop))
          index
          (scan-until source (+ index 1) end stop)))

    (: hex-char (-> Source I64 I64 Loc Char ! compile))
    (define (hex-char source start end loc)
      (let loop ((index start) (value 0))
        (cond ((and (= index end) (= start end)) (compile-error loc "invalid hexadecimal escape"))
              ((= index end) (integer->char value))
              (else (match (hex-digit (vector-ref (Source-chars source) index))
                      ((Some digit) (loop (+ index 1) (+ (* value 16) digit)))
                      ((None) (compile-error loc "invalid hexadecimal escape")))))))

    (: hex-digit (-> Char (Option I64)))
    (define (hex-digit c)
      (let ((code (char->integer c)))
        (cond ((and (<= 48 code) (<= code 57)) (Some (- code 48)))
              ((and (<= 97 code) (<= code 102)) (Some (- code 87)))
              ((and (<= 65 code) (<= code 70)) (Some (- code 55)))
              (else (None)))))

    (: character-names (List (Pair String Char)))
    (define character-names
      (list (Pair "space" #\space)
            (Pair "newline" #\newline)
            (Pair "tab" #\tab)
            (Pair "nul" (integer->char 0))
            (Pair "null" (integer->char 0))
            (Pair "return" (integer->char 13))
            (Pair "alarm" (integer->char 7))
            (Pair "backspace" (integer->char 8))
            (Pair "delete" (integer->char 127))
            (Pair "escape" (integer->char 27))))

    ;; The character `#\` names from `start` to `end`: one character, `x` and
    ;; hexadecimal digits, or a name.
    (: character-value (-> Source I64 I64 Loc Char ! compile))
    (define (character-value source start end loc)
      (let ((name (source-text source start end)))
        (cond ((= (string-length name) 0) (compile-error loc "expected a character after #\\"))
              ((= (string-length name) 1) (string-ref name 0))
              ((char=? (string-ref name 0) #\x) (hex-char source (+ start 1) end loc))
              (else
               (match (find (lambda (entry) (string=? (Pair-first entry) name)) character-names)
                 ((Some entry) (Pair-second entry))
                 ((None) (compile-error loc (string-append "unknown character name " name))))))))

    ;; ---- Tokens ----

    ;; What the reader makes of a token's text.
    (enum TokenKind
      (BooleanToken ((value Bool)))
      (IntegerToken)
      (FloatToken)
      (NameToken)
      (InvalidToken ((problem String))))

    (: token-kind (-> String TokenKind))
    (define (token-kind text)
      (cond ((or (string=? text "#t") (string=? text "#true")) (BooleanToken #t))
            ((or (string=? text "#f") (string=? text "#false")) (BooleanToken #f))
            ((string=? text ".") (InvalidToken "dotted lists are not part of Snail-Core"))
            ((char=? (string-ref text 0) #\#)
             (InvalidToken (string-append "unsupported syntax " text)))
            (else (number-kind text))))

    (: token-syntax (-> String Loc Syntax ! compile))
    (define (token-syntax text loc)
      (match (token-kind text)
        ((BooleanToken value) (Atom (DBool value) loc))
        ((IntegerToken) (Atom (integer-datum text loc) loc))
        ((FloatToken) (Atom (DFloat text) loc))
        ((NameToken) (Ident text (None) loc))
        ((InvalidToken problem) (compile-error loc problem))))

    ;; ---- Numbers ----

    ;; An optionally signed decimal integer, or a decimal float with a point
    ;; or an exponent. Any other text is a name.
    (: number-kind (-> String TokenKind))
    (define (number-kind text)
      (let* ((signed (or (char=? (string-ref text 0) #\-) (char=? (string-ref text 0) #\+)))
             (digits (if signed (substring text 1 (string-length text)) text)))
        (cond ((= (string-length digits) 0) (NameToken))
              ((not (or (char-numeric? (string-ref digits 0)) (char=? (string-ref digits 0) #\.)))
               (NameToken))
              ((every? char-numeric? (string->list digits)) (IntegerToken))
              ((float-text? digits) (FloatToken))
              (else (NameToken)))))

    ;; An integer must fit in 64 bits.
    (: integer-datum (-> String Loc Datum ! compile))
    (define (integer-datum text loc)
      (match (string->i64 text)
        ((Some value) (DInt value))
        ((None) (compile-error loc (string-append "the literal " text " does not fit I64")))))

    (: float-text? (-> String Bool))
    (define (float-text? text)
      (let ((parts (split-exponent text)))
        (and (mantissa? (Pair-first parts))
             (match (Pair-second parts)
               ((Some exponent) (exponent? exponent))
               ((None) (match (string-index (Pair-first parts) #\.) ((Some _) #t) ((None) #f)))))))

    (: split-exponent (-> String (Pair String (Option String))))
    (define (split-exponent text)
      (match (list-index (lambda (c) (or (char=? c #\e) (char=? c #\E))) (string->list text))
        ((Some index)
         (Pair (substring text 0 index) (Some (substring text (+ index 1) (string-length text)))))
        ((None) (Pair text (None)))))

    ;; Digits with at most one point, and at least one digit.
    (: mantissa? (-> String Bool))
    (define (mantissa? text)
      (let ((chars (string->list text)))
        (and (any? char-numeric? chars)
             (every? (lambda (c) (or (char-numeric? c) (char=? c #\.))) chars)
             (<= (length (filter (lambda (c) (char=? c #\.)) chars)) 1))))

    (: exponent? (-> String Bool))
    (define (exponent? text)
      (let ((digits (if (and (> (string-length text) 0)
                             (or (char=? (string-ref text 0) #\-) (char=? (string-ref text 0) #\+)))
                        (substring text 1 (string-length text))
                        text)))
        (and (> (string-length digits) 0) (every? char-numeric? (string->list digits)))))

    ;; ---- Files ----

    (: read-all (-> Source I64 (List Syntax) (List Syntax) ! compile))
    (define (read-all source index items)
      (let ((start (skip-atmosphere source index)))
        (if (at-end? source start)
            (reverse items)
            (let ((item (read-datum source start)))
              (read-all source (Pair-second item) (Cons (Pair-first item) items))))))

    (: read-text (-> String String (List Syntax) ! compile))
    (define (read-text text file)
      (read-all (make-source file text) 0 (Nil)))

    ;; ---- Generated syntax ----

    ;; One form in the encoding src/snail/shell/syntax.sld describes, every part
    ;; placed at `loc`, the recipe that produced it. A byte vector is cut
    ;; from the bytes as they are, and a number must read as it would in
    ;; text.
    (: decode-syntax (-> Bytes Loc Syntax ! compile))
    (define (decode-syntax bytes loc)
      (let ((decoded (decode-form bytes 0 loc)))
        (if (= (Pair-second decoded) (vector-length bytes))
            (Pair-first decoded)
            (malformed loc "bytes follow the library"))))

    (: decode-form (-> Bytes I64 Loc (Pair Syntax I64) ! compile))
    (define (decode-form bytes index loc)
      (let ((tag (byte-at bytes index loc)) (next (+ index 1)))
        (case tag
          ((0) (decode-list bytes next loc))
          ((1 2 3)
           (let ((text (decode-text bytes next loc)))
             (Pair (text-syntax tag (Pair-first text) loc) (Pair-second text))))
          ((4)
           (let ((code (decode-count bytes next loc)))
             (Pair (Atom (DChar (scalar (Pair-first code) loc)) loc) (Pair-second code))))
          ((5) (Pair (Atom (DBool #f) loc) next))
          ((6) (Pair (Atom (DBool #t) loc) next))
          ((7) (decode-bytes bytes next loc))
          (else (malformed loc "an unknown tag")))))

    (: decode-list (-> Bytes I64 Loc (Pair Syntax I64) ! compile))
    (define (decode-list bytes index loc)
      (let ((count (decode-count bytes index loc)))
        (let loop ((left (Pair-first count)) (index (Pair-second count)) (items (Nil)))
          (if (= left 0)
              (Pair (Form (reverse items) loc) index)
              (let ((item (decode-form bytes index loc)))
                (loop (- left 1) (Pair-second item) (Cons (Pair-first item) items)))))))

    ;; A text and the index after it.
    (: decode-text (-> Bytes I64 Loc (Pair String I64) ! compile))
    (define (decode-text bytes index loc)
      (let ((count (decode-count bytes index loc)))
        (let loop ((left (Pair-first count)) (index (Pair-second count)) (chars (Nil)))
          (if (= left 0)
              (Pair (list->string (reverse chars)) index)
              (let ((code (decode-count bytes index loc)))
                (loop (- left 1)
                      (Pair-second code)
                      (Cons (scalar (Pair-first code) loc) chars)))))))

    ;; A symbol, a number or a string, as tags 1, 2 and 3 mark them.
    (: text-syntax (-> I64 String Loc Syntax ! compile))
    (define (text-syntax tag text loc)
      (case tag
        ((1) (Ident text (None) loc))
        ((2) (Atom (generated-number text loc) loc))
        (else (Atom (DString text) loc))))

    (: decode-bytes (-> Bytes I64 Loc (Pair Syntax I64) ! compile))
    (define (decode-bytes bytes index loc)
      (let* ((count (decode-count bytes index loc))
             (start (Pair-second count))
             (end (+ start (Pair-first count))))
        (if (<= end (vector-length bytes))
            (Pair (Atom (DBytes (subvector bytes start end)) loc) end)
            (malformed loc "it ends early"))))

    ;; Seven bits to a byte, low bits first. Five bytes bound a count well
    ;; inside I64 on every host.
    (: decode-count (-> Bytes I64 Loc (Pair I64 I64) ! compile))
    (define (decode-count bytes index loc)
      (let loop ((index index) (value 0) (scale 1))
        (let ((byte (byte-at bytes index loc)))
          (cond ((< byte 128) (Pair (+ value (* byte scale)) (+ index 1)))
                ((= scale 268435456) (malformed loc "a count is too large"))
                (else (loop (+ index 1) (+ value (* (- byte 128) scale)) (* scale 128)))))))

    (: byte-at (-> Bytes I64 Loc I64 ! compile))
    (define (byte-at bytes index loc)
      (if (< index (vector-length bytes))
          (i32->i64 (u8->i32 (vector-ref bytes index)))
          (malformed loc "it ends early")))

    (: scalar (-> I64 Loc Char ! compile))
    (define (scalar code loc)
      (if (or (< code 55296) (and (> code 57343) (< code 1114112)))
          (integer->char code)
          (malformed loc "a code is not a Unicode scalar")))

    (: generated-number (-> String Loc Datum ! compile))
    (define (generated-number text loc)
      (match (if (= (string-length text) 0) (NameToken) (number-kind text))
        ((IntegerToken) (integer-datum text loc))
        ((FloatToken) (DFloat text))
        (_ (malformed loc (string-append "the number " text " does not read as one")))))

    (: malformed (All (A) (-> Loc String A ! compile)))
    (define (malformed loc problem)
      (compile-error loc (string-append "malformed generated syntax: " problem)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-read
     compile-failure)
    (import
     (only (scheme base) car)
     (snail stage0 testing))
    (begin
      ;; The located message of the source error `work` stops with, or #f
      ;; when it completes. Every unit test of a source error goes through
      ;; here.
      (define (compile-failure work)
        (match (compiling work)
          ((Err (Failed diagnostic)) (diagnostic->string diagnostic))
          (_ #f)))

      (define (test-read)
        (expect (map syntax->string
                     (read-text
                      "(define [f x] (+ x 1.5)) ; note\n\"a\\nb\" #\\a #\\space #| #| |# |# #t #;(skip) 'x -7"
                      "t"))
                (list "(define (f x) (+ x 1.5))" "\"a\\nb\"" "#\\a" "#\\ " "#t" "(quote x)" "-7"))
        (let ((forms (read-text "\n  (a\n   b)" "t.sld")))
          (expect (loc->string (syntax-loc (car forms))) "t.sld:2:3"))
        (expect (compile-failure (lambda () (read-text "(a" "t")))
                "t:1:1: unclosed list")
        (expect (map syntax->string (read-text "#u8(0 137 255) #u8( )" "t"))
                (list "#u8(0 137 255)" "#u8()"))
        (expect (compile-failure (lambda () (read-text "#u8(1 256)" "t")))
                "t:1:7: a byte is an integer from 0 to 255")
        (test-unclosed)
        (test-source-diagnostic)
        (test-decode-syntax))

      ;; The lexemes run to the end of the text; the reader says what is
      ;; missing. A string's escapes stay inside its quotes.
      (define (test-unclosed)
        (expect (compile-failure (lambda () (read-text "(a \"b" "t")))
                "t:1:4: unterminated string")
        (expect (compile-failure (lambda () (read-text "a #| #| |#" "t")))
                "t:1:11: unterminated block comment")
        (expect (compile-failure (lambda () (read-text "#\\" "t")))
                "t:1:1: expected a character after #\\")
        (expect (compile-failure (lambda () (read-text "\"\\x41\" ;" "t")))
                "t:1:1: invalid hexadecimal escape")
        (expect (map syntax->string (read-text "\"\\x41;\\\"\" #\\x41 [a]" "t"))
                (list "\"A\\\"\"" "#\\A" "(a)")))

      ;; A source error stops the compile with its diagnostic, whose column
      ;; counts Unicode scalars; one that completes stops with nothing.
      (define (test-source-diagnostic)
        (expect (compiling (lambda () (read-text "😀 )" "λ😀.sld")))
                (Err
                 (Failed (SourceDiagnostic (Loc "λ😀.sld" 1 3) "unexpected closing parenthesis"))))
        (expect (compile-failure (lambda () (read-text "()" "recovered.sld"))) #f))

      ;; (f "λ" -7 1.5 #\a #t #u8(0 200)), with a two-byte count for λ.
      (define (test-decode-syntax)
        (let ((loc (Loc "recipe.sld" 3 4))
              (bytes
               (list->vector (list 0 7 1 1 102 3 1 187 7 2 2 45 55 2 3 49 46 53 4 97 6 7 2 0 200))))
          (expect (syntax->string (decode-syntax bytes loc)) "(f \"λ\" -7 1.5 #\\a #t #u8(0 200))")
          (expect (loc->string (syntax-loc (decode-syntax bytes loc))) "recipe.sld:3:4")
          (expect
           (compile-failure (lambda () (decode-syntax (list->vector (list 0 2 1 1 102)) loc)))
           "recipe.sld:3:4: malformed generated syntax: it ends early")
          (expect (compile-failure (lambda () (decode-syntax (list->vector (list 2 1 120)) loc)))
                  "recipe.sld:3:4: malformed generated syntax: the number x does not read as one")))))
   (else)))
