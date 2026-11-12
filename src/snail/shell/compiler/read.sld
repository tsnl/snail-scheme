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
   syntax-loc
   datum=?
   bytes=?
   datum->string
   syntax->string
   compile-error
   SourceDiagnostic
   diagnostic->string
   Diagnostics
   diagnostics->list
   diagnostics->string
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
   recovering
   failures-of
   fail-if-found
   in-source-order
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

    (define (syntax-loc (syntax Syntax)) (→ Loc)
      (match syntax
        ((Atom _ loc) loc)
        ((Ident _ _ loc) loc)
        ((Form _ loc) loc)))

    ;; Syntax as source text, for diagnostics and tests.

    (define (syntax->string (syntax Syntax)) (→ String)
      (match syntax
        ((Atom value _) (datum->string value))
        ((Ident name _ _) name)
        ((Form items _) (string-append "(" (string-join (map syntax->string items) " ") ")"))))

    (define (datum->string (datum Datum)) (→ String)
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

    (define (string-literal (text String)) (→ String)
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

    (define (datum=? (a Datum) (b Datum)) (→ Bool)
      (match a
        ((DInt x) (match b ((DInt y) (= x y)) (_ #f)))
        ((DFloat x) (match b ((DFloat y) (string=? x y)) (_ #f)))
        ((DString x) (match b ((DString y) (string=? x y)) (_ #f)))
        ((DChar x) (match b ((DChar y) (char=? x y)) (_ #f)))
        ((DBytes x) (match b ((DBytes y) (bytes=? x y)) (_ #f)))
        ((DBool x) (match b ((DBool y) (eq-bool? x y)) (_ #f)))
        ((DUnit) (match b ((DUnit) #t) (_ #f)))))

    (define (bytes=? (a Bytes) (b Bytes)) (→ Bool)
      (and (= (vector-length a) (vector-length b))
           (let loop ((index 0))
             (or (= index (vector-length a))
                 (and (= (u8->i32 (vector-ref a index)) (u8->i32 (vector-ref b index)))
                      (loop (+ index 1)))))))

    (define (eq-bool? (a Bool) (b Bool)) (→ Bool)
      (if a b (not b)))

    ;; A location in line 0 is the file as a whole.
    (define (loc->string (loc Loc)) (→ String)
      (if (= (● loc line) 0)
          (● loc file)
          (string-append (● loc file)
                         ":"
                         (i64->string (● loc line))
                         ":"
                         (i64->string (● loc column)))))

    ;; ---- Source failures ----

    (struct SourceDiagnostic
      ((loc Loc)
       (message String)))

    ;; A diagnostic as a person reads it: where, then what.

    (define (diagnostic->string (diagnostic SourceDiagnostic)) (→ String)
      (string-append (loc->string (● diagnostic loc))
                     ": "
                     (● diagnostic message)))

    ;; What a failed compile found wrong, which is never nothing: the first
    ;; diagnostic, then the rest in order.
    (struct Diagnostics
      ((first SourceDiagnostic)
       (more (List SourceDiagnostic))))

    (define (diagnostics->list (diagnostics Diagnostics)) (→ (List SourceDiagnostic))
      (Cons (● diagnostics first) (● diagnostics more)))

    ;; The diagnostics a line each.

    (define (diagnostics->string (diagnostics Diagnostics)) (→ String)
      (string-join (map diagnostic->string (diagnostics->list diagnostics)) "\n"))

    ;; Every pass reports a source error by performing the compile effect's
    ;; `fail`. Nothing after the call runs: the nearest handler takes the
    ;; diagnostic, and either hands it to its caller or goes on to the
    ;; pass's next item (`recovering`).

    (define (compile-error (loc Loc) (message String)) (→ A) (! compile) (∀ A)
      (absurd (fail (Diagnostics (SourceDiagnostic loc message) (Nil)))))

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
    ;; turns the compile into a Result. `fail` carries the one diagnostic of
    ;; `compile-error`, or every one a pass collected from its items before
    ;; it stopped.
    (effect compile
      ((ctl fail (Fn Diagnostics → Never))
       (ctl need (Fn CompilerRequest → Never))))

    (enum Stop
      (Failed ((diagnostics Diagnostics)))
      (Requested ((request CompilerRequest))))

    (define (compiling (work (Fn → T ! compile e))) (→ (Result T Stop)) (! e) (∀ T e)
      (handle compile
          ((fail (lambda (diagnostics) (Err (Failed diagnostics))))
           (need (lambda (request) (Err (Requested request)))))
        (Ok (work))))

    ;; `work`'s value, or what it found wrong, so a pass can check the
    ;; rest of its items and report each one's failure together. Needing
    ;; an input is no failure of the item: the request goes on to the
    ;; compile's handler, since an implementation runs outside its handle.

    (define (recovering (work (Fn → T ! compile e)))
      (→ (Result T Diagnostics))
      (! compile e)
      (∀ T e)
      (handle compile
          ((fail (lambda (diagnostics) (Err diagnostics)))
           (need (lambda (request) (absurd (need request)))))
        (Ok (work))))

    ;; What `check` finds wrong in each item, checking every item past one
    ;; that fails, in the items' order.

    (define (failures-of (check (Fn A → Unit ! compile e)) (items (List A)))
      (→ (List SourceDiagnostic))
      (! compile e)
      (∀ A e)
      (⊨ (Copy A))
      (concatenate (map (lambda (item)
                          (match (recovering (lambda () (check item)))
                            ((Ok _) (Nil))
                            ((Err found) (diagnostics->list found))))
                        items)))

    ;; Fails the compile with `found`, unless it is empty.

    (define (fail-if-found (found (List SourceDiagnostic))) (→ Unit) (! compile)
      (match found
        ((Nil) (unit))
        ((Cons first more) (absurd (fail (Diagnostics first more))))))

    ;; The diagnostics by file, then line, then column, the order a reader
    ;; meets them; ones at the same place keep their order.

    (define (in-source-order (diagnostics (List SourceDiagnostic))) (→ (List SourceDiagnostic))
      (fold-left (lambda (sorted diagnostic) (insert-in-order diagnostic sorted))
                 (Nil)
                 diagnostics))

    (define (insert-in-order (diagnostic SourceDiagnostic) (sorted (List SourceDiagnostic)))
      (→ (List SourceDiagnostic))
      (match sorted
        ((Cons first rest)
         (if (loc<? (● diagnostic loc) (● first loc))
             (Cons diagnostic sorted)
             (Cons first (insert-in-order diagnostic rest))))
        ((Nil) (list diagnostic))))

    (define (loc<? (a Loc) (b Loc)) (→ Bool)
      (cond ((not (string=? (● a file) (● b file))) (string<? (● a file) (● b file)))
            ((= (● a line) (● b line)) (< (● a column) (● b column)))
            (else (< (● a line) (● b line)))))

    ;; ---- Line table ----

    (struct Source
      ((file String)
       (chars (Vector Char))
       (line-starts (Vector I64))))

    (define (make-source (file String) (text String)) (→ Source)
      (let ((chars (string->vector text)))
        (let loop ((index 0) (starts (list 0)))
          (cond
           ((= index (vector-length chars)) (Source file chars (list->vector (reverse starts))))
           ((char=? (vector-ref chars index) #\newline)
            (loop (+ index 1) (Cons (+ index 1) starts)))
           (else (loop (+ index 1) starts))))))

    (define (source-text (source Source) (start I64) (end I64)) (→ String)
      (vector->string (subvector (● source chars) start end)))

    ;; Binary search for the last line that starts at or before `index`.

    (define (source-loc (source Source) (index I64)) (→ Loc)
      (let ((starts (● source line-starts)))
        (let search ((low 0) (high (- (vector-length starts) 1)))
          (if (= low high)
              (Loc (● source file) (+ low 1) (+ (- index (vector-ref starts low)) 1))
              (let ((middle (quotient (+ (+ low high) 1) 2)))
                (if (<= (vector-ref starts middle) index)
                    (search middle high)
                    (search low (- middle 1))))))))

    ;; ---- Characters ----

    ;; The character at `index`, or NUL past the end; scans test `at-end?`
    ;; before they act on a NUL.

    (define (peek (source Source) (index I64)) (→ Char)
      (let ((chars (● source chars)))
        (if (< index (vector-length chars)) (vector-ref chars index) (integer->char 0))))

    (define (char-is? (source Source) (index I64) (char Char)) (→ Bool)
      (and (not (at-end? source index)) (char=? (peek source index) char)))

    (define (at-end? (source Source) (index I64)) (→ Bool)
      (>= index (vector-length (● source chars))))

    (define (delimiter? (source Source) (index I64)) (→ Bool)
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

    (define (atmosphere-at (source Source) (index I64)) (→ (Option (Pair Atmosphere I64)))
      (let ((c (peek source index)))
        (cond ((at-end? source index) (None))
              ((char-whitespace? c) (Some (Pair (Whitespace) (whitespace-end source index))))
              ((char=? c #\;) (Some (Pair (LineComment) (line-end source index))))
              ((and (char=? c #\#) (char-is? source (+ index 1) #\|))
               (Some (block-comment source (+ index 2) 1)))
              ((and (char=? c #\#) (char-is? source (+ index 1) #\;))
               (Some (Pair (DatumComment) (+ index 2))))
              (else (None)))))

    (define (whitespace-end (source Source) (index I64)) (→ I64)
      (if (and (not (at-end? source index)) (char-whitespace? (peek source index)))
          (whitespace-end source (+ index 1))
          index))

    ;; A line comment stops before its newline.

    (define (line-end (source Source) (index I64)) (→ I64)
      (if (or (at-end? source index) (char-is? source index #\newline))
          index
          (line-end source (+ index 1))))

    ;; Block comments nest.

    (define (block-comment (source Source) (index I64) (depth I64)) (→ (Pair Atmosphere I64))
      (cond ((= depth 0) (Pair (BlockComment #t) index))
            ((at-end? source index) (Pair (BlockComment #f) index))
            ((and (char-is? source index #\|) (char-is? source (+ index 1) #\#))
             (block-comment source (+ index 2) (- depth 1)))
            ((and (char-is? source index #\#) (char-is? source (+ index 1) #\|))
             (block-comment source (+ index 2) (+ depth 1)))
            (else (block-comment source (+ index 1) depth))))

    ;; The lexeme at `index`, where no atmosphere starts, and the index after
    ;; it.

    (define (lexeme-at (source Source) (index I64)) (→ (Pair Lexeme I64))
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

    (define (string-lexeme (source Source) (index I64)) (→ (Pair Lexeme I64))
      (cond ((at-end? source index) (Pair (StringLexeme #f) index))
            ((char-is? source index #\") (Pair (StringLexeme #t) (+ index 1)))
            ((char-is? source index #\\)
             (string-lexeme source (min (+ index 2) (vector-length (● source chars)))))
            (else (string-lexeme source (+ index 1)))))

    ;; `#\` takes the character after it, whatever it is, so `#\(` and `#\ `
    ;; are characters; a name runs on to a delimiter, as in `#\space`.

    (define (character-end (source Source) (index I64)) (→ I64)
      (if (at-end? source index) index (token-end source (+ index 1))))

    ;; `#u8(` opens a byte vector, as in R7RS.

    (define (bytes-opening? (source Source) (index I64)) (→ Bool)
      (and (char-is? source index #\#)
           (char-is? source (+ index 1) #\u)
           (char-is? source (+ index 2) #\8)
           (char-is? source (+ index 3) #\()))

    (define (token-end (source Source) (index I64)) (→ I64)
      (if (delimiter? source index) index (token-end source (+ index 1))))

    ;; ---- Data ----

    ;; Skips whitespace, comments, and the data that `#;` comments out.

    (define (skip-atmosphere (source Source) (index I64)) (→ I64) (! compile)
      (match (atmosphere-at source index)
        ((Some (Pair (BlockComment #f) end))
         (compile-error (source-loc source end) "unterminated block comment"))
        ((Some (Pair (DatumComment) end))
         (skip-atmosphere source (● (read-datum source end) second)))
        ((Some (Pair _ end)) (skip-atmosphere source end))
        ((None) index)))

    ;; The datum starting at `index`, and the index after it.

    (define (read-datum (source Source) (index I64)) (→ (Pair Syntax I64)) (! compile)
      (let ((start (skip-atmosphere source index)))
        (read-lexeme source start (lexeme-at source start))))

    ;; The datum that the lexeme at `start` begins, and the index after it.

    (define (read-lexeme (source Source) (start I64) (lexeme (Pair Lexeme I64)))
      (→ (Pair Syntax I64))
      (! compile)
      (let ((loc (source-loc source start)) (end (● lexeme second)))
        (match (● lexeme first)
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

    (define (read-bytes (source Source) (index I64) (loc Loc) (chunks (List Bytes)))
      (→ (Pair Syntax I64))
      (! compile)
      (let* ((chunk (read-byte-chunk source index loc))
             (bytes (● chunk first))
             (next (● chunk second)))
        (if (< (vector-length bytes) byte-chunk)
            (Pair (Atom (DBytes (vector-concatenate (reverse (Cons bytes chunks)))) loc) next)
            (read-bytes source next loc (Cons bytes chunks)))))

    (define byte-chunk 4096)

    ;; Up to `byte-chunk` bytes, and the index after them: past the closing
    ;; parenthesis when fewer remain.

    (define (read-byte-chunk (source Source) (index I64) (loc Loc)) (→ (Pair Bytes I64)) (! compile)
      (let loop ((index index) (bytes (Nil)) (count 0))
        (let ((start (skip-atmosphere source index)))
          (cond ((= count byte-chunk) (Pair (list->vector (reverse bytes)) start))
                ((at-end? source start) (compile-error loc "unclosed byte vector"))
                ((char-is? source start #\)) (Pair (list->vector (reverse bytes)) (+ start 1)))
                (else (let ((end (token-end source start)))
                        (loop end (Cons (byte-token source start end) bytes) (+ count 1))))))))

    (define (byte-token (source Source) (start I64) (end I64)) (→ U8) (! compile)
      (let loop ((index start) (value 0))
        (cond ((and (= index end) (< start end) (<= value 255)) (i32->u8 (i64->i32 value)))
              ((or (= index end)
                   (> value 255)
                   (not (char-numeric? (vector-ref (● source chars) index))))
               (compile-error (source-loc source start) "a byte is an integer from 0 to 255"))
              (else (loop (+ index 1)
                          (+ (* value 10)
                             (digit-value (vector-ref (● source chars) index))))))))

    (define (read-quote (source Source) (index I64) (loc Loc)) (→ (Pair Syntax I64)) (! compile)
      (let ((quoted (read-datum source index)))
        (Pair (Form (list (Ident "quote" (None) loc) (● quoted first)) loc)
              (● quoted second))))

    (define (read-list (source Source) (index I64) (close Char) (loc Loc) (items (List Syntax)))
      (→ (Pair Syntax I64))
      (! compile)
      (let* ((start (skip-atmosphere source index)) (lexeme (lexeme-at source start)))
        (match (● lexeme first)
          ((EndOfText) (compile-error loc "unclosed list"))
          ((ListClose c)
           (if (char=? c close)
               (Pair (Form (reverse items) loc) (● lexeme second))
               (compile-error (source-loc source start) "mismatched closing parenthesis")))
          (_ (let ((item (read-lexeme source start lexeme)))
               (read-list source (● item second) close loc (Cons (● item first) items)))))))

    ;; ---- Strings and characters ----

    ;; The text of a string whose characters run from `start` to its closing
    ;; quote at `close`. A backslash there always has a character after it,
    ;; which the string's lexeme skipped.

    (define (string-value (source Source) (start I64) (close I64) (loc Loc)) (→ String) (! compile)
      (let loop ((index start) (chars (Nil)))
        (cond ((= index close) (list->string (reverse chars)))
              ((char-is? source index #\\)
               (let ((escaped (read-escape source (+ index 1) close loc)))
                 (loop (● escaped second) (Cons (● escaped first) chars))))
              (else (loop (+ index 1) (Cons (peek source index) chars))))))

    (define (read-escape (source Source) (index I64) (close I64) (loc Loc))
      (→ (Pair Char I64))
      (! compile)
      (let ((c (peek source index)))
        (cond ((char=? c #\n) (Pair #\newline (+ index 1)))
              ((char=? c #\t) (Pair #\tab (+ index 1)))
              ((char=? c #\r) (Pair (integer->char 13) (+ index 1)))
              ((char=? c #\0) (Pair (integer->char 0) (+ index 1)))
              ((char=? c #\x) (hex-escape source (+ index 1) close loc))
              ((or (char=? c #\\) (char=? c #\") (char=? c #\|)) (Pair c (+ index 1)))
              (else (compile-error loc "unknown string escape")))))

    ;; `\x41;`: hexadecimal digits and a semicolon, inside the string.

    (define (hex-escape (source Source) (index I64) (close I64) (loc Loc))
      (→ (Pair Char I64))
      (! compile)
      (let ((end (scan-until source index close #\;)))
        (if (= end close)
            (compile-error loc "invalid hexadecimal escape")
            (Pair (hex-char source index end loc) (+ end 1)))))

    (define (scan-until (source Source) (index I64) (end I64) (stop Char)) (→ I64)
      (if (or (= index end) (char-is? source index stop))
          index
          (scan-until source (+ index 1) end stop)))

    (define (hex-char (source Source) (start I64) (end I64) (loc Loc)) (→ Char) (! compile)
      (let loop ((index start) (value 0))
        (cond ((and (= index end) (= start end)) (compile-error loc "invalid hexadecimal escape"))
              ((= index end) (integer->char value))
              (else (match (hex-digit (vector-ref (● source chars) index))
                      ((Some digit) (loop (+ index 1) (+ (* value 16) digit)))
                      ((None) (compile-error loc "invalid hexadecimal escape")))))))

    (define (hex-digit (c Char)) (→ (Option I64))
      (let ((code (char->integer c)))
        (cond ((and (<= 48 code) (<= code 57)) (Some (- code 48)))
              ((and (<= 97 code) (<= code 102)) (Some (- code 87)))
              ((and (<= 65 code) (<= code 70)) (Some (- code 55)))
              (else (None)))))

    (define character-names (→ (List (Pair String Char)))
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

    (define (character-value (source Source) (start I64) (end I64) (loc Loc)) (→ Char) (! compile)
      (let ((name (source-text source start end)))
        (cond ((= (string-length name) 0) (compile-error loc "expected a character after #\\"))
              ((= (string-length name) 1) (string-ref name 0))
              ((char=? (string-ref name 0) #\x) (hex-char source (+ start 1) end loc))
              (else
               (match (find (lambda (entry) (string=? (● entry first) name)) character-names)
                 ((Some entry) (● entry second))
                 ((None) (compile-error loc (string-append "unknown character name " name))))))))

    ;; ---- Tokens ----

    ;; What the reader makes of a token's text.
    (enum TokenKind
      (BooleanToken ((value Bool)))
      (IntegerToken)
      (FloatToken)
      (NameToken)
      (InvalidToken ((problem String))))

    (define (token-kind (text String)) (→ TokenKind)
      (cond ((or (string=? text "#t") (string=? text "#true")) (BooleanToken #t))
            ((or (string=? text "#f") (string=? text "#false")) (BooleanToken #f))
            ((string=? text ".") (InvalidToken "dotted lists are not part of Snail-Core"))
            ((char=? (string-ref text 0) #\#)
             (InvalidToken (string-append "unsupported syntax " text)))
            (else (number-kind text))))

    (define (token-syntax (text String) (loc Loc)) (→ Syntax) (! compile)
      (match (token-kind text)
        ((BooleanToken value) (Atom (DBool value) loc))
        ((IntegerToken) (Atom (integer-datum text loc) loc))
        ((FloatToken) (Atom (DFloat text) loc))
        ((NameToken) (Ident text (None) loc))
        ((InvalidToken problem) (compile-error loc problem))))

    ;; ---- Numbers ----

    ;; An optionally signed decimal integer, or a decimal float with a point
    ;; or an exponent. Any other text is a name.

    (define (number-kind (text String)) (→ TokenKind)
      (let* ((signed (or (char=? (string-ref text 0) #\-) (char=? (string-ref text 0) #\+)))
             (digits (if signed (substring text 1 (string-length text)) text)))
        (cond ((= (string-length digits) 0) (NameToken))
              ((not (or (char-numeric? (string-ref digits 0)) (char=? (string-ref digits 0) #\.)))
               (NameToken))
              ((every? char-numeric? (string->list digits)) (IntegerToken))
              ((float-text? digits) (FloatToken))
              (else (NameToken)))))

    ;; An integer must fit in 64 bits.

    (define (integer-datum (text String) (loc Loc)) (→ Datum) (! compile)
      (match (string->i64 text)
        ((Some value) (DInt value))
        ((None) (compile-error loc (string-append "the literal " text " does not fit I64")))))

    (define (float-text? (text String)) (→ Bool)
      (let ((parts (split-exponent text)))
        (and (mantissa? (● parts first))
             (match (● parts second)
               ((Some exponent) (exponent? exponent))
               ((None) (match (string-index (● parts first) #\.) ((Some _) #t) ((None) #f)))))))

    (define (split-exponent (text String)) (→ (Pair String (Option String)))
      (match (list-index (lambda (c) (or (char=? c #\e) (char=? c #\E))) (string->list text))
        ((Some index)
         (Pair (substring text 0 index) (Some (substring text (+ index 1) (string-length text)))))
        ((None) (Pair text (None)))))

    ;; Digits with at most one point, and at least one digit.

    (define (mantissa? (text String)) (→ Bool)
      (let ((chars (string->list text)))
        (and (any? char-numeric? chars)
             (every? (lambda (c) (or (char-numeric? c) (char=? c #\.))) chars)
             (<= (length (filter (lambda (c) (char=? c #\.)) chars)) 1))))

    (define (exponent? (text String)) (→ Bool)
      (let ((digits (if (and (> (string-length text) 0)
                             (or (char=? (string-ref text 0) #\-) (char=? (string-ref text 0) #\+)))
                        (substring text 1 (string-length text))
                        text)))
        (and (> (string-length digits) 0) (every? char-numeric? (string->list digits)))))

    ;; ---- Files ----

    (define (read-all (source Source) (index I64) (items (List Syntax)))
      (→ (List Syntax))
      (! compile)
      (let ((start (skip-atmosphere source index)))
        (if (at-end? source start)
            (reverse items)
            (let ((item (read-datum source start)))
              (read-all source (● item second) (Cons (● item first) items))))))

    (define (read-text (text String) (file String)) (→ (List Syntax)) (! compile)
      (read-all (make-source file text) 0 (Nil)))

    ;; ---- Generated syntax ----

    ;; One form in the encoding src/snail/shell/syntax.sld describes, every part
    ;; placed at `loc`, the recipe that produced it. A byte vector is cut
    ;; from the bytes as they are, and a number must read as it would in
    ;; text.

    (define (decode-syntax (bytes Bytes) (loc Loc)) (→ Syntax) (! compile)
      (let ((decoded (decode-form bytes 0 loc)))
        (if (= (● decoded second) (vector-length bytes))
            (● decoded first)
            (malformed loc "bytes follow the library"))))

    (define (decode-form (bytes Bytes) (index I64) (loc Loc)) (→ (Pair Syntax I64)) (! compile)
      (let ((tag (byte-at bytes index loc)) (next (+ index 1)))
        (case tag
          ((0) (decode-list bytes next loc))
          ((1 2 3)
           (let ((text (decode-text bytes next loc)))
             (Pair (text-syntax tag (● text first) loc) (● text second))))
          ((4)
           (let ((code (decode-count bytes next loc)))
             (Pair (Atom (DChar (scalar (● code first) loc)) loc) (● code second))))
          ((5) (Pair (Atom (DBool #f) loc) next))
          ((6) (Pair (Atom (DBool #t) loc) next))
          ((7) (decode-bytes bytes next loc))
          (else (malformed loc "an unknown tag")))))

    (define (decode-list (bytes Bytes) (index I64) (loc Loc)) (→ (Pair Syntax I64)) (! compile)
      (let ((count (decode-count bytes index loc)))
        (let loop ((left (● count first)) (index (● count second)) (items (Nil)))
          (if (= left 0)
              (Pair (Form (reverse items) loc) index)
              (let ((item (decode-form bytes index loc)))
                (loop (- left 1) (● item second) (Cons (● item first) items)))))))

    ;; A text and the index after it.

    (define (decode-text (bytes Bytes) (index I64) (loc Loc)) (→ (Pair String I64)) (! compile)
      (let ((count (decode-count bytes index loc)))
        (let loop ((left (● count first)) (index (● count second)) (chars (Nil)))
          (if (= left 0)
              (Pair (list->string (reverse chars)) index)
              (let ((code (decode-count bytes index loc)))
                (loop (- left 1)
                      (● code second)
                      (Cons (scalar (● code first) loc) chars)))))))

    ;; A symbol, a number or a string, as tags 1, 2 and 3 mark them.

    (define (text-syntax (tag I64) (text String) (loc Loc)) (→ Syntax) (! compile)
      (case tag
        ((1) (Ident text (None) loc))
        ((2) (Atom (generated-number text loc) loc))
        (else (Atom (DString text) loc))))

    (define (decode-bytes (bytes Bytes) (index I64) (loc Loc)) (→ (Pair Syntax I64)) (! compile)
      (let* ((count (decode-count bytes index loc))
             (start (● count second))
             (end (+ start (● count first))))
        (if (<= end (vector-length bytes))
            (Pair (Atom (DBytes (subvector bytes start end)) loc) end)
            (malformed loc "it ends early"))))

    ;; Seven bits to a byte, low bits first. Five bytes bound a count well
    ;; inside I64 on every host.

    (define (decode-count (bytes Bytes) (index I64) (loc Loc)) (→ (Pair I64 I64)) (! compile)
      (let loop ((index index) (value 0) (scale 1))
        (let ((byte (byte-at bytes index loc)))
          (cond ((< byte 128) (Pair (+ value (* byte scale)) (+ index 1)))
                ((= scale 268435456) (malformed loc "a count is too large"))
                (else (loop (+ index 1) (+ value (* (- byte 128) scale)) (* scale 128)))))))

    (define (byte-at (bytes Bytes) (index I64) (loc Loc)) (→ I64) (! compile)
      (if (< index (vector-length bytes))
          (i32->i64 (u8->i32 (vector-ref bytes index)))
          (malformed loc "it ends early")))

    (define (scalar (code I64) (loc Loc)) (→ Char) (! compile)
      (if (or (< code 55296) (and (> code 57343) (< code 1114112)))
          (integer->char code)
          (malformed loc "a code is not a Unicode scalar")))

    (define (generated-number (text String) (loc Loc)) (→ Datum) (! compile)
      (match (if (= (string-length text) 0) (NameToken) (number-kind text))
        ((IntegerToken) (integer-datum text loc))
        ((FloatToken) (DFloat text))
        (_ (malformed loc (string-append "the number " text " does not read as one")))))

    (define (malformed (loc Loc) (problem String)) (→ A) (! compile) (∀ A)
      (compile-error loc (string-append "malformed generated syntax: " problem)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-read
     compile-failure)
    (import
     (only (chezscheme) car)
     (snail stage0 testing))
    (begin
      ;; The located message of the source error `work` stops with, or #f
      ;; when it completes. Every unit test of a source error goes through
      ;; here.
      (define compile-failure
        (lambda (work) (match (compiling work)
                         ((Err (Failed diagnostics)) (diagnostics->string diagnostics))
                         (_ #f))))

      (define test-read
        (lambda () (expect (map syntax->string
                                (read-text
                                 "(define [f x] (+ x 1.5)) ; note\n\"a\\nb\" #\\a #\\space #| #| |# |# #t #;(skip) 'x -7"
                                 "t"))
                           (list "(define (f x) (+ x 1.5))"
                                 "\"a\\nb\""
                                 "#\\a"
                                 "#\\ "
                                 "#t"
                                 "(quote x)"
                                 "-7"))
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
                (test-decode-syntax)))

      ;; The lexemes run to the end of the text; the reader says what is
      ;; missing. A string's escapes stay inside its quotes.
      (define test-unclosed
        (lambda () (expect (compile-failure (lambda () (read-text "(a \"b" "t")))
                           "t:1:4: unterminated string")
                (expect (compile-failure (lambda () (read-text "a #| #| |#" "t")))
                        "t:1:11: unterminated block comment")
                (expect (compile-failure (lambda () (read-text "#\\" "t")))
                        "t:1:1: expected a character after #\\")
                (expect (compile-failure (lambda () (read-text "\"\\x41\" ;" "t")))
                        "t:1:1: invalid hexadecimal escape")
                (expect (map syntax->string (read-text "\"\\x41;\\\"\" #\\x41 [a]" "t"))
                        (list "\"A\\\"\"" "#\\A" "(a)"))))

      ;; A source error stops the compile with its diagnostic, whose column
      ;; counts Unicode scalars; one that completes stops with nothing.
      (define test-source-diagnostic
        (lambda () (expect (compiling (lambda () (read-text "😀 )" "λ😀.sld")))
                           (Err (Failed (Diagnostics (SourceDiagnostic (Loc "λ😀.sld" 1 3)
                                                                       "unexpected closing parenthesis")
                                                     (Nil)))))
                (expect (compile-failure (lambda () (read-text "()" "recovered.sld"))) #f)
                (test-recovering)))

      ;; A failure inside `recovering` is its answer, so the work around
      ;; it goes on; a need passes through it to the compile's handler.
      (define test-recovering
        (lambda () (expect (compiling (lambda () (recovering (lambda () (read-text ")" "t.sld")))))
                           (Ok (Err (Diagnostics (SourceDiagnostic (Loc "t.sld" 1 1)
                                                                   "unexpected closing parenthesis")
                                                 (Nil)))))
                (expect (compiling
                         (lambda () (recovering (lambda () (absurd (need (GenerateInput "k")))))))
                        (Err (Requested (GenerateInput "k"))))))

      ;; (f "λ" -7 1.5 #\a #t #u8(0 200)), with a two-byte count for λ.
      (define test-decode-syntax
        (lambda () (let ((loc (Loc "recipe.sld" 3 4))
                         (bytes
                          (list->vector
                           (list 0 7 1 1 102 3 1 187 7 2 2 45 55 2 3 49 46 53 4 97 6 7 2 0 200))))
                     (expect (syntax->string (decode-syntax bytes loc))
                             "(f \"λ\" -7 1.5 #\\a #t #u8(0 200))")
                     (expect (loc->string (syntax-loc (decode-syntax bytes loc))) "recipe.sld:3:4")
                     (expect
                      (compile-failure
                       (lambda () (decode-syntax (list->vector (list 0 2 1 1 102)) loc)))
                      "recipe.sld:3:4: malformed generated syntax: it ends early")
                     (expect (compile-failure
                              (lambda () (decode-syntax (list->vector (list 2 1 120)) loc)))
                             "recipe.sld:3:4: malformed generated syntax: the number x does not read as one"))))))
   (else)))
