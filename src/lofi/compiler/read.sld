;; Text to located syntax. The reader is a recursive descent over a vector
;; of characters; a position is just an index, and line and column are
;; recovered from a table of line starts only when a location is needed.
;; The syntax a `generate-library` producer writes arrives as bytes instead,
;; and is decoded without passing through text.
(define-library (lofi compiler read)
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
   datum->string
   syntax->string
   syntax->key
   compile-error
   read-text
   decode-syntax)
  (import
   (lofi base))
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

    ;; Syntax as text that keys a build. A byte vector shows only its length
    ;; and a hash of its bytes, so a library that embeds megabytes keys on a
    ;; few characters.
    (: syntax->key (-> Syntax String))
    (define (syntax->key syntax)
      (match syntax
        ((Atom (DBytes value) _) (string-append "#u8<" (i64->string (vector-length value)) ":" (i64->string (bytes-hash value)) ">"))
        ((Atom value _) (datum->string value))
        ((Ident name _ _) name)
        ((Form items _) (string-append "(" (string-join (map syntax->key items) " ") ")"))))

    ;; 32-bit FNV-1a over bytes, as `fnv-1a` hashes text.
    (: bytes-hash (-> Bytes I64))
    (define (bytes-hash bytes)
      (vector-fold (lambda (hash byte) (i64-and (* (i64-xor hash (i32->i64 (u8->i32 byte))) 16777619) 4294967295)) 2166136261 bytes))

    (: datum->string (-> Datum String))
    (define (datum->string datum)
      (match datum
        ((DInt value) (i64->string value))
        ((DFloat text) text)
        ((DString value) (string-literal value))
        ((DChar value) (string-append "#\\" (list->string (list value))))
        ((DBytes value) (string-append "#u8(" (string-join (map (lambda (byte) (i64->string (i32->i64 (u8->i32 byte)))) (vector->list value)) " ") ")"))
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
                 (and (= (u8->i32 (vector-ref a index)) (u8->i32 (vector-ref b index))) (loop (+ index 1)))))))

    (: eq-bool? (-> Bool Bool Bool))
    (define (eq-bool? a b)
      (if a b (not b)))

    (: loc->string (-> Loc String))
    (define (loc->string loc)
      (string-append (Loc-file loc) ":" (i64->string (Loc-line loc)) ":" (i64->string (Loc-column loc))))

    ;; Every pass reports a source error through this one procedure.
    (: compile-error (All (A) (-> Loc String A)))
    (define (compile-error loc message)
      (panic (string-append (loc->string loc) ": " message)))

    ;; ---- Line table ----

    (struct Source
      ((file String)
       (chars (Vector Char))
       (line-starts (Vector I64))))

    (: make-source (-> String String Source))
    (define (make-source file text)
      (let ((chars (string->vector text)))
        (let loop ((index 0) (starts (list 0)))
          (cond ((= index (vector-length chars)) (Source file chars (list->vector (reverse starts))))
                ((char=? (vector-ref chars index) #\newline) (loop (+ index 1) (Cons (+ index 1) starts)))
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

    ;; ---- Characters and atmosphere ----

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
        (or (at-end? source index) (char-whitespace? c) (char=? c #\() (char=? c #\)) (char=? c #\[) (char=? c #\])
            (char=? c #\") (char=? c #\;) (char=? c #\'))))

    ;; Skips whitespace, line comments, nested block comments and datum comments.
    (: skip-atmosphere (-> Source I64 I64))
    (define (skip-atmosphere source index)
      (let ((c (peek source index)))
        (cond ((at-end? source index) index)
              ((char-whitespace? c) (skip-atmosphere source (+ index 1)))
              ((char=? c #\;) (skip-atmosphere source (skip-line source index)))
              ((and (char=? c #\#) (char-is? source (+ index 1) #\|)) (skip-atmosphere source (skip-block source (+ index 2) 1)))
              ((and (char=? c #\#) (char-is? source (+ index 1) #\;))
               (skip-atmosphere source (Pair-second (read-datum source (+ index 2)))))
              (else index))))

    (: skip-line (-> Source I64 I64))
    (define (skip-line source index)
      (if (or (at-end? source index) (char-is? source index #\newline)) index (skip-line source (+ index 1))))

    (: skip-block (-> Source I64 I64 I64))
    (define (skip-block source index depth)
      (cond ((= depth 0) index)
            ((at-end? source index) (compile-error (source-loc source index) "unterminated block comment"))
            ((and (char-is? source index #\|) (char-is? source (+ index 1) #\#)) (skip-block source (+ index 2) (- depth 1)))
            ((and (char-is? source index #\#) (char-is? source (+ index 1) #\|)) (skip-block source (+ index 2) (+ depth 1)))
            (else (skip-block source (+ index 1) depth))))

    ;; ---- Data ----

    ;; The datum starting at `index`, and the index after it.
    (: read-datum (-> Source I64 (Pair Syntax I64)))
    (define (read-datum source index)
      (let* ((start (skip-atmosphere source index)) (loc (source-loc source start)) (c (peek source start)))
        (cond ((at-end? source start) (compile-error loc "expected a datum before the end of the file"))
              ((char=? c #\() (read-list source (+ start 1) #\) loc (Nil)))
              ((char=? c #\[) (read-list source (+ start 1) #\] loc (Nil)))
              ((or (char=? c #\)) (char=? c #\])) (compile-error loc "unexpected closing parenthesis"))
              ((char=? c #\") (read-string-literal source (+ start 1) loc (Nil)))
              ((char=? c #\') (read-quote source (+ start 1) loc))
              ((and (char=? c #\#) (char-is? source (+ start 1) #\\)) (read-character source (+ start 2) loc))
              ((bytes-opening? source start) (read-bytes source (+ start 4) loc (Nil)))
              (else (read-token source start loc)))))

    ;; `#u8(` opens a byte vector, as in R7RS.
    (: bytes-opening? (-> Source I64 Bool))
    (define (bytes-opening? source index)
      (and (char-is? source index #\#) (char-is? source (+ index 1) #\u) (char-is? source (+ index 2) #\8)
           (char-is? source (+ index 3) #\()))

    ;; The bytes of `#u8(...)`, each an integer from 0 to 255. Images make
    ;; literals of millions of bytes, so they gather a chunk at a time into
    ;; packed vectors, which are joined at the closing parenthesis.
    (: read-bytes (-> Source I64 Loc (List Bytes) (Pair Syntax I64)))
    (define (read-bytes source index loc chunks)
      (let* ((chunk (read-byte-chunk source index loc)) (bytes (Pair-first chunk)) (next (Pair-second chunk)))
        (if (< (vector-length bytes) byte-chunk)
            (Pair (Atom (DBytes (vector-concatenate (reverse (Cons bytes chunks)))) loc) next)
            (read-bytes source next loc (Cons bytes chunks)))))

    (define byte-chunk 4096)

    ;; Up to `byte-chunk` bytes, and the index after them: past the closing
    ;; parenthesis when fewer remain.
    (: read-byte-chunk (-> Source I64 Loc (Pair Bytes I64)))
    (define (read-byte-chunk source index loc)
      (let loop ((index index) (bytes (Nil)) (count 0))
        (let ((start (skip-atmosphere source index)))
          (cond ((= count byte-chunk) (Pair (list->vector (reverse bytes)) start))
                ((at-end? source start) (compile-error loc "unclosed byte vector"))
                ((char-is? source start #\)) (Pair (list->vector (reverse bytes)) (+ start 1)))
                (else (let ((end (token-end source start)))
                        (loop end (Cons (byte-token source start end) bytes) (+ count 1))))))))

    (: byte-token (-> Source I64 I64 U8))
    (define (byte-token source start end)
      (let loop ((index start) (value 0))
        (cond ((and (= index end) (< start end) (<= value 255)) (i32->u8 (i64->i32 value)))
              ((or (= index end) (> value 255) (not (char-numeric? (vector-ref (Source-chars source) index))))
               (compile-error (source-loc source start) "a byte is an integer from 0 to 255"))
              (else (loop (+ index 1) (+ (* value 10) (digit-value (vector-ref (Source-chars source) index))))))))

    (: read-quote (-> Source I64 Loc (Pair Syntax I64)))
    (define (read-quote source index loc)
      (let ((quoted (read-datum source index)))
        (Pair (Form (list (Ident "quote" (None) loc) (Pair-first quoted)) loc) (Pair-second quoted))))

    (: read-list (-> Source I64 Char Loc (List Syntax) (Pair Syntax I64)))
    (define (read-list source index close loc items)
      (let* ((start (skip-atmosphere source index)) (c (peek source start)))
        (cond ((at-end? source start) (compile-error loc "unclosed list"))
              ((char=? c close) (Pair (Form (reverse items) loc) (+ start 1)))
              ((or (char=? c #\)) (char=? c #\])) (compile-error (source-loc source start) "mismatched closing parenthesis"))
              (else (let ((item (read-datum source start)))
                      (read-list source (Pair-second item) close loc (Cons (Pair-first item) items)))))))

    (: read-string-literal (-> Source I64 Loc (List Char) (Pair Syntax I64)))
    (define (read-string-literal source index loc chars)
      (let ((c (peek source index)))
        (cond ((at-end? source index) (compile-error loc "unterminated string"))
              ((char=? c #\") (Pair (Atom (DString (list->string (reverse chars))) loc) (+ index 1)))
              ((char=? c #\\)
               (let ((escaped (read-escape source (+ index 1) loc)))
                 (read-string-literal source (Pair-second escaped) loc (Cons (Pair-first escaped) chars))))
              (else (read-string-literal source (+ index 1) loc (Cons c chars))))))

    (: read-escape (-> Source I64 Loc (Pair Char I64)))
    (define (read-escape source index loc)
      (let ((c (peek source index)))
        (cond ((at-end? source index) (compile-error loc "unterminated string"))
              ((char=? c #\n) (Pair #\newline (+ index 1)))
              ((char=? c #\t) (Pair #\tab (+ index 1)))
              ((char=? c #\r) (Pair (integer->char 13) (+ index 1)))
              ((char=? c #\0) (Pair (integer->char 0) (+ index 1)))
              ((char=? c #\x)
               (let ((end (scan-until source (+ index 1) #\;)))
                 (Pair (hex-char source (+ index 1) end loc) (+ end 1))))
              ((or (char=? c #\\) (char=? c #\") (char=? c #\|)) (Pair c (+ index 1)))
              (else (compile-error loc "unknown string escape")))))

    (: scan-until (-> Source I64 Char I64))
    (define (scan-until source index stop)
      (if (or (at-end? source index) (char-is? source index stop)) index (scan-until source (+ index 1) stop)))

    (: hex-char (-> Source I64 I64 Loc Char))
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
      (list (Pair "space" #\space) (Pair "newline" #\newline) (Pair "tab" #\tab) (Pair "nul" (integer->char 0))
            (Pair "null" (integer->char 0)) (Pair "return" (integer->char 13)) (Pair "alarm" (integer->char 7))
            (Pair "backspace" (integer->char 8)) (Pair "delete" (integer->char 127)) (Pair "escape" (integer->char 27))))

    ;; `#\a`, `#\space` or `#\x41`. The first character is always part of the
    ;; name, so `#\(` and `#\ ` read as themselves.
    (: read-character (-> Source I64 Loc (Pair Syntax I64)))
    (define (read-character source index loc)
      (let* ((end (token-end source (+ index 1))) (name (source-text source index end)))
        (cond ((= (string-length name) 1) (Pair (Atom (DChar (string-ref name 0)) loc) end))
              ((char=? (string-ref name 0) #\x) (Pair (Atom (DChar (hex-char source (+ index 1) end loc)) loc) end))
              (else (match (find (lambda (entry) (string=? (Pair-first entry) name)) character-names)
                      ((Some entry) (Pair (Atom (DChar (Pair-second entry)) loc) end))
                      ((None) (compile-error loc (string-append "unknown character name " name))))))))

    (: token-end (-> Source I64 I64))
    (define (token-end source index)
      (if (delimiter? source index) index (token-end source (+ index 1))))

    (: read-token (-> Source I64 Loc (Pair Syntax I64)))
    (define (read-token source start loc)
      (let ((end (token-end source start)))
        (Pair (token-syntax (source-text source start end) loc) end)))

    (: token-syntax (-> String Loc Syntax))
    (define (token-syntax text loc)
      (cond ((or (string=? text "#t") (string=? text "#true")) (Atom (DBool #t) loc))
            ((or (string=? text "#f") (string=? text "#false")) (Atom (DBool #f) loc))
            ((string=? text ".") (compile-error loc "dotted lists are not part of Lofi"))
            ((char=? (string-ref text 0) #\#) (compile-error loc (string-append "unsupported syntax " text)))
            (else (match (number-token text loc)
                    ((Some datum) (Atom datum loc))
                    ((None) (Ident text (None) loc))))))

    ;; ---- Numbers ----

    ;; An optionally signed decimal integer, which must fit in 64 bits, or a
    ;; decimal float with a point or an exponent.
    (: number-token (-> String Loc (Option Datum)))
    (define (number-token text loc)
      (let* ((signed (or (char=? (string-ref text 0) #\-) (char=? (string-ref text 0) #\+)))
             (digits (if signed (substring text 1 (string-length text)) text)))
        (cond ((= (string-length digits) 0) (None))
              ((not (or (char-numeric? (string-ref digits 0)) (char=? (string-ref digits 0) #\.))) (None))
              ((every? char-numeric? (string->list digits))
               (match (string->i64 text)
                 ((Some value) (Some (DInt value)))
                 ((None) (compile-error loc (string-append "the literal " text " does not fit I64")))))
              ((float-text? digits) (Some (DFloat text)))
              (else (None)))))

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
        ((Some index) (Pair (substring text 0 index) (Some (substring text (+ index 1) (string-length text)))))
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
      (let ((digits (if (and (> (string-length text) 0) (or (char=? (string-ref text 0) #\-) (char=? (string-ref text 0) #\+)))
                        (substring text 1 (string-length text))
                        text)))
        (and (> (string-length digits) 0) (every? char-numeric? (string->list digits)))))

    ;; ---- Files ----

    (: read-all (-> Source I64 (List Syntax) (List Syntax)))
    (define (read-all source index items)
      (let ((start (skip-atmosphere source index)))
        (if (at-end? source start)
            (reverse items)
            (let ((item (read-datum source start)))
              (read-all source (Pair-second item) (Cons (Pair-first item) items))))))

    (: read-text (-> String String (List Syntax)))
    (define (read-text text file)
      (read-all (make-source file text) 0 (Nil)))

    ;; ---- Generated syntax ----

    ;; One form in the encoding lib/lofi/syntax.sld describes, every part
    ;; placed at `loc`, the recipe that produced it. A byte vector is cut
    ;; from the bytes as they are, and a number must read as it would in
    ;; text.
    (: decode-syntax (-> Bytes Loc Syntax))
    (define (decode-syntax bytes loc)
      (let ((decoded (decode-form bytes 0 loc)))
        (if (= (Pair-second decoded) (vector-length bytes))
            (Pair-first decoded)
            (malformed loc "bytes follow the library"))))

    (: decode-form (-> Bytes I64 Loc (Pair Syntax I64)))
    (define (decode-form bytes index loc)
      (let ((next (+ index 1)))
        (case (byte-at bytes index loc)
          ((0) (decode-list bytes next loc))
          ((1) (decode-text-as bytes next loc (lambda (text) (Ident text (None) loc))))
          ((2) (decode-text-as bytes next loc (lambda (text) (Atom (generated-number text loc) loc))))
          ((3) (decode-text-as bytes next loc (lambda (text) (Atom (DString text) loc))))
          ((4) (let ((code (decode-count bytes next loc))) (Pair (Atom (DChar (scalar (Pair-first code) loc)) loc) (Pair-second code))))
          ((5) (Pair (Atom (DBool #f) loc) next))
          ((6) (Pair (Atom (DBool #t) loc) next))
          ((7) (decode-bytes bytes next loc))
          (else (malformed loc "an unknown tag")))))

    (: decode-list (-> Bytes I64 Loc (Pair Syntax I64)))
    (define (decode-list bytes index loc)
      (let ((count (decode-count bytes index loc)))
        (let loop ((left (Pair-first count)) (index (Pair-second count)) (items (Nil)))
          (if (= left 0)
              (Pair (Form (reverse items) loc) index)
              (let ((item (decode-form bytes index loc)))
                (loop (- left 1) (Pair-second item) (Cons (Pair-first item) items)))))))

    (: decode-text-as (-> Bytes I64 Loc (-> String Syntax) (Pair Syntax I64)))
    (define (decode-text-as bytes index loc make)
      (let ((count (decode-count bytes index loc)))
        (let loop ((left (Pair-first count)) (index (Pair-second count)) (chars (Nil)))
          (if (= left 0)
              (Pair (make (list->string (reverse chars))) index)
              (let ((code (decode-count bytes index loc)))
                (loop (- left 1) (Pair-second code) (Cons (scalar (Pair-first code) loc) chars)))))))

    (: decode-bytes (-> Bytes I64 Loc (Pair Syntax I64)))
    (define (decode-bytes bytes index loc)
      (let* ((count (decode-count bytes index loc)) (start (Pair-second count)) (end (+ start (Pair-first count))))
        (if (<= end (vector-length bytes))
            (Pair (Atom (DBytes (subvector bytes start end)) loc) end)
            (malformed loc "it ends early"))))

    ;; Seven bits to a byte, low bits first. Five bytes bound a count well
    ;; inside I64 on every host.
    (: decode-count (-> Bytes I64 Loc (Pair I64 I64)))
    (define (decode-count bytes index loc)
      (let loop ((index index) (value 0) (scale 1))
        (let ((byte (byte-at bytes index loc)))
          (cond ((< byte 128) (Pair (+ value (* byte scale)) (+ index 1)))
                ((= scale 268435456) (malformed loc "a count is too large"))
                (else (loop (+ index 1) (+ value (* (- byte 128) scale)) (* scale 128)))))))

    (: byte-at (-> Bytes I64 Loc I64))
    (define (byte-at bytes index loc)
      (if (< index (vector-length bytes))
          (i32->i64 (u8->i32 (vector-ref bytes index)))
          (malformed loc "it ends early")))

    (: scalar (-> I64 Loc Char))
    (define (scalar code loc)
      (if (or (< code 55296) (and (> code 57343) (< code 1114112)))
          (integer->char code)
          (malformed loc "a code is not a Unicode scalar")))

    (: generated-number (-> String Loc Datum))
    (define (generated-number text loc)
      (match (if (= (string-length text) 0) (None) (number-token text loc))
        ((Some datum) datum)
        ((None) (malformed loc (string-append "the number " text " does not read as one")))))

    (: malformed (All (A) (-> Loc String A)))
    (define (malformed loc problem)
      (compile-error loc (string-append "malformed generated syntax: " problem)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-read)
    (import
     (only (scheme base) car guard error-object-message)
     (lofi testing))
    (begin
      (define (test-read)
        (expect (map syntax->string
                     (read-text "(define [f x] (+ x 1.5)) ; note\n\"a\\nb\" #\\a #\\space #| #| |# |# #t #;(skip) 'x -7" "t"))
                (list "(define (f x) (+ x 1.5))" "\"a\\nb\"" "#\\a" "#\\ " "#t" "(quote x)" "-7"))
        (let ((forms (read-text "\n  (a\n   b)" "t.sld")))
          (expect (loc->string (syntax-loc (car forms))) "t.sld:2:3"))
        (expect (guard (failure (#t (error-object-message failure))) (read-text "(a" "t"))
                "t:1:1: unclosed list")
        (expect (map syntax->string (read-text "#u8(0 137 255) #u8( )" "t")) (list "#u8(0 137 255)" "#u8()"))
        (expect (guard (failure (#t (error-object-message failure))) (read-text "#u8(1 256)" "t"))
                "t:1:7: a byte is an integer from 0 to 255")
        (test-decode-syntax))

      ;; (f "λ" -7 1.5 #\a #t #u8(0 200)), with a two-byte count for λ.
      (define (test-decode-syntax)
        (let ((loc (Loc "recipe.sld" 3 4))
              (bytes (list->vector (list 0 7 1 1 102 3 1 187 7 2 2 45 55 2 3 49 46 53 4 97 6 7 2 0 200))))
          (expect (syntax->string (decode-syntax bytes loc)) "(f \"λ\" -7 1.5 #\\a #t #u8(0 200))")
          (expect (loc->string (syntax-loc (decode-syntax bytes loc))) "recipe.sld:3:4")
          (expect (guard (failure (#t (error-object-message failure))) (decode-syntax (list->vector (list 0 2 1 1 102)) loc))
                  "recipe.sld:3:4: malformed generated syntax: it ends early")
          (expect (guard (failure (#t (error-object-message failure))) (decode-syntax (list->vector (list 2 1 120)) loc))
                  "recipe.sld:3:4: malformed generated syntax: the number x does not read as one")))))
   (else)))
