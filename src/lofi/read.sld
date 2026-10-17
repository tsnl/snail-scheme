;; Incremental typed datum input. Rust owns UTF-8 decoding and port lookahead;
;; Lofi owns tokens, syntax, mutable pair fields and every returned datum.
(define-library (lofi read)
  (export ReadResult read read-end read-value read-error read-end?
          read-value-datum read-error-message read-value!
          test-read)
  (import
   (lofi base)
   (lofi io)
   (lofi datum)
   (lofi bytes))


  ;; ---- A datum, normal EOF and malformed input are distinct results ----

  (begin
    (def Token (datatype ()
                 (value-token
                  (datum Datum))
                 (end-token)
                 (close-token)
                 (dot-token)
                 (open-token
                  (kind I64))
                 (prefix-token
                  (name String))
                 (error-token
                  (message String))))
    (def TextResult (datatype ()
                      (text-value
                       (text String))
                      (text-error
                       (message String))))
    (def Escape (datatype ()
                  (escaped-character
                   (value Char))
                  (escaped-gap)
                  (escape-error
                   (message String))))

    (def read-end? (-> ReadResult Bool)
         (lambda (result)
           (match result ((read-end) #t) ((read-value value) #f) ((read-error message) #f))))

    (def read-value! (-> ReadResult Datum)
         (lambda (result)
           (match result ((read-value value) value)
                  ((read-end) (datum-fail "read: expected a datum, received end of file"))
                  ((read-error message) (datum-fail (string-append "read: " message))))))

    (def read (-> InputPort ReadResult)
         (lambda (port) (token-datum port (next-token port))))

    ;; ---- Port lookahead survives every reader invocation ----

    (define-extern raw-whitespace "snail.library" "snail:datum/whitespace" (-> Char I32))

    (def character-code (-> CharacterResult I64)
         (lambda (result)
           (match result ((character-end) (ann -1 I64)) ((character-value value) (char->integer value)))))

    (def peek-code (-> InputPort I64)
         (lambda (port) (character-code (peek-char port))))

    (def take-code (-> InputPort I64)
         (lambda (port) (character-code (read-char port))))

    (def code=? (-> I64 Char Bool)
         (lambda (code character) (= code (char->integer character))))

    (def take-if (-> InputPort Char Bool)
         (lambda (port character)
           (if (code=? (peek-code port) character) (begin (read-char port) #t) #f)))

    (def whitespace? (-> I64 Bool)
         (lambda (code)
           (if (>= code (ann 0 I64)) (i32-eq (raw-whitespace (integer->char code)) (ann 1 I32)) #f)))

    (def delimiter? (-> I64 Bool)
         (lambda (code)
           (if (< code (ann 0 I64))
               #t
               (if (whitespace? code)
                   #t
                   (if (code=? code #\()
                       #t
                       (if (code=? code #\))
                           #t
                           (if (code=? code #\")
                               #t
                               (if (code=? code #\;)
                                   #t
                                   (if (code=? code #\|)
                                       #t
                                       (if (code=? code #\')
                                           #t
                                           (if (code=? code #\`)
                                               #t
                                               (if (code=? code #\,)
                                                   #t
                                                   (if (code=? code #\[)
                                                       #t
                                                       (if (code=? code #\]) #t (if (code=? code #\{) #t (code=? code #\}))))))))))))))))

    ;; ---- A geometrically growing Unicode token buffer ----

    (def Buffer (datatype ()
                  (buffer
                   (text (Ref String) buffer-text)
                   (count (Ref I64) buffer-count))))

    (def new-buffer (-> Buffer)
         (lambda () (buffer (ref (make-string (ann 32 I64))) (ref (ann 0 I64)))))

    (def append-character! (-> Buffer Char Unit)
         (lambda (buffer character)
           (begin (let count (ref-get (buffer-count buffer)))
                  (begin
                    (if (= count (string-length (ref-get (buffer-text buffer))))
                        (begin (grow-buffer! buffer count)
                               (unit))
                        (unit))
                    (string-set! (ref-get (buffer-text buffer)) count character)
                    (ref-set! (buffer-count buffer) (+ count (ann 1 I64)))))))

    (def grow-buffer! (-> Buffer I64 Unit)
         (lambda (buffer count)
           (if (>= count (ann 4294967294 I64))
               (datum-fail "read: token exceeds String capacity")
               (begin (let size (if (> count (ann 2147483647 I64)) (ann 4294967294 I64) (* count (ann 2 I64))))
                      (begin (let grown (make-string size))
                             (begin
                               (string-copy! grown (ann 0 I64) (ref-get (buffer-text buffer)) (ann 0 I64) count)
                               (ref-set! (buffer-text buffer) grown)))))))

    (def buffer-string (-> Buffer String)
         (lambda (buffer)
           (substring (ref-get (buffer-text buffer)) (ann 0 I64) (ref-get (buffer-count buffer)))))

    (def read-word (-> InputPort I64 String)
         (lambda (port first)
           (begin (let buffer (new-buffer))
                  (begin
                    (append-character! buffer (integer->char first))
                    (begin
                      (def loop
                           (lambda ()
                             (if (delimiter? (peek-code port))
                                 (buffer-string buffer)
                                 (begin (append-character! buffer (integer->char (take-code port))) (loop)))))
                      (loop))))))

    (def ascii-lower (-> String String)
         (lambda (text)
           (begin (let result (string-copy text))
                  (begin
                    (def loop
                         (lambda (index)
                           (if (= index (string-length result))
                               result
                               (begin (let code (char->integer (string-ref result index)))
                                      (begin
                                        (if (if (>= code (ann 65 I64)) (<= code (ann 90 I64)) #f)
                                            (begin
                                              (string-set! result index (integer->char (+ code (ann 32 I64))))
                                              (unit))
                                            (unit))
                                        (loop (+ index (ann 1 I64))))))))
                    (loop (ann 0 I64))))))

    ;; ---- Layout includes complete, recursively parsed datum comments ----

    (def skip-line (-> InputPort Unit)
         (lambda (port)
           (begin (let code (take-code port))
                  (if (if (< code (ann 0 I64)) #t (if (code=? code #\newline) #t (code=? code #\return)))
                      (unit)
                      (begin (skip-line port)
                             (unit))))))

    (def skip-block (-> InputPort I64 Bool)
         (lambda (port depth)
           (begin (let code (take-code port))
                  (if (< code (ann 0 I64))
                      #f
                      (if (if (code=? code #\#) (take-if port #\|) #f)
                          (skip-block port (+ depth (ann 1 I64)))
                          (if (if (code=? code #\|) (take-if port #\#) #f)
                              (if (= depth (ann 1 I64)) #t (skip-block port (- depth (ann 1 I64))))
                              (skip-block port depth)))))))

    (def discard-datum (-> InputPort Token)
         (lambda (port)
           (match (read port)
             ((read-value value) (next-token port))
             ((read-end) (error-token "datum comment requires a datum"))
             ((read-error message) (error-token message)))))

    (def next-token (-> InputPort Token)
         (lambda (port)
           (begin (let code (take-code port))
                  (if (< code (ann 0 I64))
                      (end-token)
                      (if (whitespace? code)
                          (next-token port)
                          (if (code=? code #\;)
                              (begin (skip-line port) (next-token port))
                              (ordinary-token port code)))))))

    ;; ---- Token dispatch exposes all supported syntax in one place ----

    (def ordinary-token (-> InputPort I64 Token)
         (lambda (port code)
           (if (code=? code #\()
               (open-token (ann 0 I64))
               (if (code=? code #\))
                   (close-token)
                   (if (code=? code #\')
                       (prefix-token "quote")
                       (if (code=? code #\`)
                           (prefix-token "quasiquote")
                           (if (code=? code #\,)
                               (prefix-token (if (take-if port #\@) "unquote-splicing" "unquote"))
                               (if (code=? code #\")
                                   (quoted-token port #\" #f)
                                   (if (code=? code #\|)
                                       (quoted-token port #\| #t)
                                       (if (code=? code #\#)
                                           (sharp-token port)
                                           (if (if (code=? code #\[)
                                                   #t
                                                   (if (code=? code #\]) #t (if (code=? code #\{) #t (code=? code #\}))))
                                               (error-token "unsupported datum delimiter")
                                               (atom-token (read-word port code)))))))))))))

    (def sharp-token (-> InputPort Token)
         (lambda (port)
           (begin (let code (take-code port))
                  (if (< code (ann 0 I64))
                      (error-token "incomplete # syntax")
                      (if (code=? code #\()
                          (open-token (ann 1 I64))
                          (if (code=? code #\;)
                              (discard-datum port)
                              (if (code=? code #\|)
                                  (if (skip-block port (ann 1 I64)) (next-token port) (error-token "unterminated block comment"))
                                  (if (code=? code #\\)
                                      (character-token port)
                                      (if (if (code=? code #\u) #t (code=? code #\U))
                                          (bytevector-token port)
                                          (if (code=? code #\!)
                                              (error-token "reader case directives are not supported")
                                              (if (if (>= code (ann 48 I64)) (<= code (ann 57 I64)) #f)
                                                  (error-token "datum labels are not supported")
                                                  (sharp-word (string-append "#" (read-word port code))))))))))))))

    (def bytevector-token (-> InputPort Token)
         (lambda (port)
           (if (if (take-if port #\8) (take-if port #\() #f)
               (open-token (ann 2 I64))
               (error-token "expected #u8( bytevector syntax"))))

    (def sharp-word (-> String Token)
         (lambda (text)
           (begin (let folded (ascii-lower text))
                  (if (if (string=? folded "#t") #t (string=? folded "#true"))
                      (value-token (datum-boolean #t))
                      (if (if (string=? folded "#f") #t (string=? folded "#false"))
                          (value-token (datum-boolean #f))
                          (match (string->number text)
                            ((parsed-number number) (value-token (datum-number number)))
                            ((number-error message) (error-token message))
                            ((not-a-number) (error-token "invalid or unsupported # numeric syntax"))))))))

    (def atom-token (-> String Token)
         (lambda (text)
           (if (string=? text ".")
               (dot-token)
               (match (string->atom text)
                 ((read-value value) (value-token value))
                 ((read-error message) (error-token message)) ((read-end) (unreachable))))))

    ;; ---- Strings and escaped symbols share scalar escapes ----

    (def quoted-token (-> InputPort Char Bool Token)
         (lambda (port end symbol?)
           (match (read-text port end)
             ((text-value text) (value-token (if symbol? (datum-symbol (string->symbol text)) (datum-string text))))
             ((text-error message) (error-token message)))))

    (def read-text (-> InputPort Char TextResult)
         (lambda (port end) (text-loop port end (new-buffer))))

    (def text-loop (-> InputPort Char Buffer TextResult)
         (lambda (port end buffer)
           (begin (let code (take-code port))
                  (if (< code (ann 0 I64))
                      (text-error "unterminated string or escaped symbol")
                      (if (code=? code end)
                          (text-value (buffer-string buffer))
                          (if (code=? code #\\)
                              (continue-escape port end buffer (read-escape port end))
                              (begin
                                (append-character! buffer (text-character port end code))
                                (text-loop port end buffer))))))))

    (def text-character (-> InputPort Char I64 Char)
         (lambda (port end code)
           (if (if (char=? end #\") (code=? code #\return) #f)
               (begin (take-if port #\newline) #\newline)
               (integer->char code))))

    (def continue-escape (-> InputPort Char Buffer Escape TextResult)
         (lambda (port end buffer escape)
           (match escape
             ((escaped-character value)
              (begin (append-character! buffer value) (text-loop port end buffer)))
             ((escaped-gap) (text-loop port end buffer)) ((escape-error message) (text-error message)))))

    (def read-escape (-> InputPort Char Escape)
         (lambda (port end)
           (begin (let code (take-code port))
                  (if (code=? code #\a)
                      (escaped-character (integer->char (ann 7 I64)))
                      (if (code=? code #\b)
                          (escaped-character (integer->char (ann 8 I64)))
                          (if (code=? code #\t)
                              (escaped-character #\tab)
                              (if (code=? code #\n)
                                  (escaped-character #\newline)
                                  (if (code=? code #\r)
                                      (escaped-character #\return)
                                      (if (if (code=? code #\") #t (if (code=? code #\|) #t (code=? code #\\)))
                                          (escaped-character (integer->char code))
                                          (if (code=? code #\x)
                                              (hex-escape port (ann 0 I64) (ann 0 I64))
                                              (if (if (char=? end #\") (continuation-space? code) #f)
                                                  (line-continuation port code)
                                                  (escape-error "unknown or incomplete escape"))))))))))))

    (def continuation-space? (-> I64 Bool)
         (lambda (code)
           (if (code=? code #\space)
               #t
               (if (code=? code #\tab) #t (if (code=? code #\newline) #t (code=? code #\return))))))

    (def skip-horizontal (-> InputPort Unit)
         (lambda (port)
           (if (if (code=? (peek-code port) #\space) #t (code=? (peek-code port) #\tab))
               (begin
                 (read-char port) (skip-horizontal port)
                 (unit))
               (unit))))

    (def line-continuation (-> InputPort I64 Escape)
         (lambda (port code)
           (if (if (code=? code #\space) #t (code=? code #\tab))
               (line-continuation port (take-code port))
               (if (if (code=? code #\newline) #t (code=? code #\return))
                   (begin (if (code=? code #\return) (begin (take-if port #\newline) (unit)) (unit))
                          (skip-horizontal port) (escaped-gap))
                   (escape-error "expected newline in string continuation")))))

    ;; ---- Hexadecimal escapes validate Unicode before constructing Char ----

    (def hex-digit (-> I64 I64)
         (lambda (code)
           (if (if (>= code (ann 48 I64)) (<= code (ann 57 I64)) #f)
               (- code (ann 48 I64))
               (if (if (>= code (ann 65 I64)) (<= code (ann 70 I64)) #f)
                   (- code (ann 55 I64))
                   (if (if (>= code (ann 97 I64)) (<= code (ann 102 I64)) #f) (- code (ann 87 I64)) (ann -1 I64))))))

    (def unicode-scalar? (-> I64 Bool)
         (lambda (value)
           (if (>= value (ann 0 I64)) (if (<= value (ann 1114111 I64)) (if (< value (ann 55296 I64)) #t (> value (ann 57343 I64))) #f) #f)))

    (def finish-hex (-> I64 I64 Escape)
         (lambda (value count)
           (if (if (> count (ann 0 I64)) (unicode-scalar? value) #f)
               (escaped-character (integer->char value))
               (escape-error "invalid Unicode scalar escape"))))

    (def hex-escape (-> InputPort I64 I64 Escape)
         (lambda (port value count)
           (begin (let code (take-code port))
                  (if (code=? code #\;)
                      (finish-hex value count)
                      (begin (let digit (hex-digit code))
                             (if (if (< digit (ann 0 I64)) #t (> value (ann 69631 I64)))
                                 (escape-error "invalid hexadecimal escape")
                                 (hex-escape port (+ (* value (ann 16 I64)) digit) (+ count (ann 1 I64)))))))))

    (def hex-character (-> String Escape)
         (lambda (text)
           (begin
             (def loop
                  (lambda (index value)
                    (if (= index (string-length text))
                        (finish-hex value (- index (ann 1 I64)))
                        (begin (let digit (hex-digit (char->integer (string-ref text index))))
                               (if (if (< digit (ann 0 I64)) #t (> value (ann 69631 I64)))
                                   (escape-error "invalid character code")
                                   (loop (+ index (ann 1 I64)) (+ (* value (ann 16 I64)) digit)))))))
             (loop (ann 1 I64) (ann 0 I64)))))

    ;; ---- Character literals can contain a delimiter as their one scalar ----

    (def character-token (-> InputPort Token)
         (lambda (port)
           (begin (let code (take-code port))
                  (if (< code (ann 0 I64))
                      (error-token "incomplete character literal")
                      (if (delimiter? code)
                          (value-token (datum-character (integer->char code)))
                          (named-character-token (read-word port code)))))))

    (def named-character-token (-> String Token)
         (lambda (text)
           (if (= (string-length text) (ann 1 I64))
               (value-token (datum-character (string-ref text (ann 0 I64))))
               (match (named-character (ascii-lower text))
                 ((escaped-character value) (value-token (datum-character value)))
                 ((escape-error message) (error-token message)) ((escaped-gap) (unreachable))))))

    (def named-character (-> String Escape)
         (lambda (text)
           (if (string=? text "alarm")
               (escaped-character (integer->char (ann 7 I64)))
               (if (string=? text "backspace")
                   (escaped-character (integer->char (ann 8 I64)))
                   (if (string=? text "delete")
                       (escaped-character (integer->char (ann 127 I64)))
                       (if (string=? text "escape")
                           (escaped-character (integer->char (ann 27 I64)))
                           (if (string=? text "newline")
                               (escaped-character #\newline)
                               (if (string=? text "null")
                                   (escaped-character (integer->char (ann 0 I64)))
                                   (if (string=? text "return")
                                       (escaped-character #\return)
                                       (if (string=? text "space")
                                           (escaped-character #\space)
                                           (if (string=? text "tab")
                                               (escaped-character #\tab)
                                               (if (char=? (string-ref text (ann 0 I64)) #\x)
                                                   (hex-character text)
                                                   (escape-error "unknown character literal")))))))))))))

    ;; ---- Containers preserve source order and dotted-tail structure ----

    (def token-datum (-> InputPort Token ReadResult)
         (lambda (port token)
           (match token
             ((value-token value) (read-value value)) ((end-token) (read-end))
             ((error-token message) (read-error message))
             ((open-token kind) (container-loop port kind (empty-list )))
             ((prefix-token name) (prefix-datum port name))
             ((close-token) (read-error "unexpected closing parenthesis"))
             ((dot-token) (read-error "unexpected dot")))))

    (def prefix-datum (-> InputPort String ReadResult)
         (lambda (port name)
           (match (read port)
             ((read-value value) (read-value (datum-cons (datum-symbol (string->symbol name))
                                                         (datum-cons value (datum-null)))))
             ((read-end) (read-error "quote abbreviation requires a datum"))
             ((read-error message) (read-error message)))))

    (def container-loop (-> InputPort I64 (List Datum) ReadResult)
         (lambda (port kind reversed)
           (begin (let token (next-token port))
                  (match token
                    ((close-token) (finish-container kind reversed))
                    ((end-token) (read-error "unexpected end of input inside container"))
                    ((dot-token) (if (if (= kind (ann 0 I64)) (not (null? reversed)) #f)
                                     (dotted-tail port reversed)
                                     (read-error "dot requires a preceding list element")))
                    ((error-token message) (read-error message))
                    ((value-token value) (container-loop port kind (cons value reversed)))
                    ((open-token nested-kind) (container-element port kind reversed (token-datum port token)))
                    ((prefix-token name) (container-element port kind reversed (token-datum port token)))))))

    (def container-element (-> InputPort I64 (List Datum) ReadResult ReadResult)
         (lambda (port kind reversed result)
           (match result
             ((read-value value) (container-loop port kind (cons value reversed)))
             ((read-error message) (read-error message)) ((read-end) (unreachable)))))

    (def dotted-tail (-> InputPort (List Datum) ReadResult)
         (lambda (port reversed)
           (match (read port)
             ((read-value tail) (match (next-token port)
                                  ((close-token) (read-value (attach-reversed reversed tail)))
                                  ((error-token message) (read-error message))
                                  ((value-token value) (read-error "extra datum after dotted tail"))
                                  ((end-token) (read-error "unclosed dotted list"))
                                  ((dot-token) (read-error "extra dot after dotted tail"))
                                  ((open-token kind) (read-error "extra container after dotted tail"))
                                  ((prefix-token name) (read-error "extra abbreviation after dotted tail"))))
             ((read-end) (read-error "missing dotted tail"))
             ((read-error message) (read-error message)))))

    (def attach-reversed (-> (List Datum) Datum Datum)
         (lambda (reversed tail)
           (if (null? reversed)
               tail
               (attach-reversed (cdr reversed) (datum-cons (car reversed) tail)))))

    (def reverse-elements (-> (List Datum) (List Datum))
         (lambda (elements)
           (begin
             (def loop
                  (lambda (elements result)
                    (if (null? elements) result (loop (cdr elements) (cons (car elements) result)))))
             (loop elements (empty-list )))))

    (def finish-container (-> I64 (List Datum) ReadResult)
         (lambda (kind reversed)
           (if (= kind (ann 0 I64))
               (read-value (attach-reversed reversed (datum-null)))
               (if (= kind (ann 1 I64))
                   (read-value (datum-vector (list->vector (reverse-elements reversed))))
                   (finish-bytes reversed)))))

    (def finish-bytes (-> (List Datum) ReadResult)
         (lambda (reversed)
           (begin (let count (begin
                               (def loop
                                    (lambda (tail count)
                                      (if (null? tail) count (loop (cdr tail) (+ count (ann 1 I64))))))
                               (loop reversed (ann 0 I64))))
                  (fill-bytes reversed (make-bytevector count) count))))

    (def byte-value (-> Datum I64)
         (lambda (value)
           (if (datum-number? value)
               (match (datum-number-value value) ((exact-number value) value)
                      ((rational-number value) (ann -1 I64)) ((inexact-number value) (ann -1 I64)) ((complex-number real imaginary) (ann -1 I64)))
               (ann -1 I64))))

    (def fill-bytes (-> (List Datum) Bytevector I64 ReadResult)
         (lambda (reversed result index)
           (if (null? reversed)
               (read-value (datum-bytevector result))
               (begin (let value (byte-value (car reversed)))
                      (if (if (< value (ann 0 I64)) #t (> value (ann 255 I64)))
                          (read-error "bytevector requires exact bytes in [0,255]")
                          (begin (bytevector-u8-set! result (- index (ann 1 I64)) value)
                                 (fill-bytes (cdr reversed) result (- index (ann 1 I64)))))))))

    ;; ---- Tests ----

    ;; Test entry points are ordinary Lofi exports; no feature expansion is required.

    (def test-delimiter-members (-> (List I64) Bool)
         (lambda (codes)
           (if (null? codes)
               #t
               (if (delimiter? (car codes)) (test-delimiter-members (cdr codes)) #f))))

    (def test-read (-> I64)
         (lambda ()
           (if (if (test-delimiter-members (cons (ann 40 I64) (cons (ann 41 I64) (cons (ann 34 I64) (cons (ann 59 I64) (cons (ann 124 I64) (cons (ann 39 I64) (cons (ann 96 I64) (cons (ann 44 I64) (cons (ann 91 I64) (cons (ann 93 I64) (cons (ann 123 I64) (cons (ann 125 I64) (empty-list ))))))))))))))
                   (if (delimiter? (ann -1 I64))
                       (if (delimiter? (ann 9 I64))
                           (if (delimiter? (ann 10 I64))
                               (if (delimiter? (ann 32 I64))
                                   (if (delimiter? (ann 160 I64))
                                       (if (delimiter? (ann 8195 I64))
                                           (if (not (delimiter? (ann 46 I64)))
                                               (if (not (delimiter? (ann 48 I64)))
                                                   (if (not (delimiter? (ann 65 I64))) (if (not (delimiter? (ann 233 I64))) (not (delimiter? (ann 128512 I64))) #f) #f)
                                                   #f)
                                               #f)
                                           #f)
                                       #f)
                                   #f)
                               #f)
                           #f)
                       #f)
                   #f)
               (ann 42 I64)
               (ann 0 I64))))))
