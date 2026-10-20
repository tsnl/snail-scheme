;; Text to located syntax. The reader is a recursive descent over a string; a
;; position is just an index, and line and column are recovered from a table
;; of line starts only when a location is needed.
(define-library (lofi compiler read)
  (export
   Loc
   Loc-file
   Loc-line
   Loc-column
   loc->string
   Atom
   Ident
   Ident-name
   Ident-mark
   Ident-loc
   Form
   Form-items
   Form-loc
   syntax-loc
   syntax->datum
   compile-error
   read-text
   read-file)
  (import
   (scheme base)
   (scheme char)
   (scheme file)
   (lofi compiler shim))
  (begin

    ;; ---- Locations and syntax ----

    (struct Loc
      ((file String)
       (line I64)
       (column I64)))

    ;; An atom is an integer, float, string, character or boolean. An
    ;; identifier's mark is #f from the reader; the expander marks identifiers
    ;; that a macro template introduces.
    (enum Syntax
      (Atom
       ((value Datum)
        (loc Loc)))
      (Ident
       ((name Symbol)
        (mark Mark)
        (loc Loc)))
      (Form
       ((items (List Syntax))
        (loc Loc))))

    (define (syntax-loc syntax)
      (match syntax
        ((Atom _ loc) loc)
        ((Ident _ _ loc) loc)
        ((Form _ loc) loc)))

    (define (syntax->datum syntax)
      (match syntax
        ((Atom value _) value)
        ((Ident name _ _) name)
        ((Form items _) (map syntax->datum items))))

    (define (loc->string loc)
      (string-append (Loc-file loc) ":" (number->string (Loc-line loc))
                     ":" (number->string (Loc-column loc))))

    ;; Every pass reports a source error through this one procedure.
    (define (compile-error loc message . irritants)
      (apply error (string-append (if loc (loc->string loc) "lofi") ": " message) irritants))

    ;; ---- Line table ----

    ;; The text is held as a vector: indexing a host string can take time
    ;; proportional to its length.
    (struct Source
      ((file String)
       (chars (Vector Char))
       (line-starts (Vector I64))))

    (define (make-source file text)
      (let ((chars (string->vector text)))
        (let loop ((index 0) (starts '(0)))
          (cond ((= index (vector-length chars)) (Source file chars (list->vector (reverse starts))))
                ((char=? (vector-ref chars index) #\newline) (loop (+ index 1) (cons (+ index 1) starts)))
                (else (loop (+ index 1) starts))))))

    (define (source-text source start end)
      (vector->string (Source-chars source) start end))

    ;; Binary search for the last line that starts at or before `index`.
    (define (source-loc source index)
      (let ((starts (Source-line-starts source)))
        (let search ((low 0) (high (- (vector-length starts) 1)))
          (if (= low high)
              (Loc (Source-file source) (+ low 1) (+ (- index (vector-ref starts low)) 1))
              (let ((middle (quotient (+ low high 1) 2)))
                (if (<= (vector-ref starts middle) index)
                    (search middle high)
                    (search low (- middle 1))))))))

    ;; ---- Characters and atmosphere ----

    (define (char-at source index)
      (let ((chars (Source-chars source)))
        (if (< index (vector-length chars)) (vector-ref chars index) #f)))

    (define (delimiter? char)
      (or (not char) (char-whitespace? char) (memv char '(#\( #\) #\[ #\] #\" #\; #\'))))

    ;; Skips whitespace, line comments, nested block comments and datum comments.
    (define (skip-atmosphere source index)
      (let ((char (char-at source index)))
        (cond ((not char) index)
              ((char-whitespace? char) (skip-atmosphere source (+ index 1)))
              ((char=? char #\;) (skip-atmosphere source (skip-line source index)))
              ((and (char=? char #\#) (eqv? (char-at source (+ index 1)) #\|))
               (skip-atmosphere source (skip-block source (+ index 2) 1)))
              ((and (char=? char #\#) (eqv? (char-at source (+ index 1)) #\;))
               (let-values (((datum next) (read-datum source (+ index 2))))
                 (skip-atmosphere source next)))
              (else index))))

    (define (skip-line source index)
      (let ((char (char-at source index)))
        (if (or (not char) (char=? char #\newline)) index (skip-line source (+ index 1)))))

    (define (skip-block source index depth)
      (let ((char (char-at source index)) (next (char-at source (+ index 1))))
        (cond ((= depth 0) index)
              ((not char) (compile-error (source-loc source index) "unterminated block comment"))
              ((and (char=? char #\|) (eqv? next #\#)) (skip-block source (+ index 2) (- depth 1)))
              ((and (char=? char #\#) (eqv? next #\|)) (skip-block source (+ index 2) (+ depth 1)))
              (else (skip-block source (+ index 1) depth)))))

    ;; ---- Data ----

    ;; Returns the datum starting at `index` and the index after it.
    (define (read-datum source index)
      (let* ((start (skip-atmosphere source index)) (char (char-at source start))
             (loc (source-loc source start)))
        (cond ((not char) (compile-error loc "expected a datum before the end of the file"))
              ((memv char '(#\( #\[)) (read-list source (+ start 1) (if (char=? char #\() #\) #\]) loc '()))
              ((memv char '(#\) #\])) (compile-error loc "unexpected closing parenthesis"))
              ((char=? char #\") (read-string-literal source (+ start 1) loc '()))
              ((char=? char #\')
               (let-values (((datum next) (read-datum source (+ start 1))))
                 (values (Form (list (Ident 'quote #f loc) datum) loc) next)))
              ((and (char=? char #\#) (eqv? (char-at source (+ start 1)) #\\))
               (read-character source (+ start 2) loc))
              (else (read-token source start loc)))))

    (define (read-list source index close loc items)
      (let* ((start (skip-atmosphere source index)) (char (char-at source start)))
        (cond ((not char) (compile-error loc "unclosed list"))
              ((eqv? char close) (values (Form (reverse items) loc) (+ start 1)))
              ((memv char '(#\) #\])) (compile-error (source-loc source start) "mismatched closing parenthesis"))
              (else (let-values (((item next) (read-datum source start)))
                      (read-list source next close loc (cons item items)))))))

    (define (read-string-literal source index loc chars)
      (let ((char (char-at source index)))
        (cond ((not char) (compile-error loc "unterminated string"))
              ((char=? char #\") (values (Atom (list->string (reverse chars)) loc) (+ index 1)))
              ((char=? char #\\)
               (let-values (((escaped next) (read-escape source (+ index 1) loc)))
                 (read-string-literal source next loc (cons escaped chars))))
              (else (read-string-literal source (+ index 1) loc (cons char chars))))))

    (define (read-escape source index loc)
      (let ((char (char-at source index)))
        (case char
          ((#\n) (values #\newline (+ index 1)))
          ((#\t) (values #\tab (+ index 1)))
          ((#\r) (values #\return (+ index 1)))
          ((#\0) (values (integer->char 0) (+ index 1)))
          ((#\\ #\" #\|) (values char (+ index 1)))
          ((#\x) (let ((end (scan-until source (+ index 1) #\;)))
                   (values (hex-char source (+ index 1) end loc) (+ end 1))))
          (else (compile-error loc "unknown string escape" char)))))

    (define (scan-until source index stop)
      (let ((char (char-at source index)))
        (if (or (not char) (char=? char stop)) index (scan-until source (+ index 1) stop))))

    (define (hex-char source start end loc)
      (let ((value (string->number (source-text source start end) 16)))
        (unless (and value (exact-integer? value)) (compile-error loc "invalid hexadecimal escape"))
        (integer->char value)))

    (define character-names
      '(("space" . #\space) ("newline" . #\newline) ("tab" . #\tab) ("nul" . #\null)
        ("return" . #\return) ("alarm" . #\alarm) ("backspace" . #\backspace)
        ("delete" . #\delete) ("escape" . #\escape) ("null" . #\null)))

    ;; `#\a`, `#\space` or `#\x41`. The first character is always part of the
    ;; name, so `#\(` and `#\ ` read as themselves.
    (define (read-character source index loc)
      (let* ((end (token-end source (+ index 1))) (name (source-text source index end)))
        (cond ((= (string-length name) 1) (values (Atom (string-ref name 0) loc) end))
              ((assoc name character-names) => (lambda (entry) (values (Atom (cdr entry) loc) end)))
              ((char=? (string-ref name 0) #\x) (values (Atom (hex-char source (+ index 1) end loc) loc) end))
              (else (compile-error loc "unknown character name" name)))))

    (define (token-end source index)
      (if (delimiter? (char-at source index)) index (token-end source (+ index 1))))

    (define (read-token source start loc)
      (let* ((end (token-end source start)) (text (source-text source start end)))
        (values (token-syntax text loc) end)))

    ;; Only a token that starts like a number is parsed as one; the host's
    ;; number parser is slow, and most tokens are identifiers.
    (define (token-syntax text loc)
      (cond ((member text '("#t" "#true")) (Atom #t loc))
            ((member text '("#f" "#false")) (Atom #f loc))
            ((and (numeric-start? text) (string->number text)) => (lambda (number) (Atom number loc)))
            ((char=? (string-ref text 0) #\#) (compile-error loc "unsupported syntax" text))
            ((string=? text ".") (compile-error loc "dotted lists are not part of Lofi"))
            (else (Ident (string->symbol text) #f loc))))

    (define (numeric-start? text)
      (let ((first (string-ref text 0)))
        (or (char-numeric? first)
            (and (memv first '(#\+ #\- #\.)) (> (string-length text) 1)
                 (or (char-numeric? (string-ref text 1)) (char=? (string-ref text 1) #\.) (memv (string-ref text 1) '(#\i #\n)))))))

    ;; ---- Files ----

    (define (read-all source index items)
      (let ((start (skip-atmosphere source index)))
        (if (char-at source start)
            (let-values (((item next) (read-datum source start)))
              (read-all source next (cons item items)))
            (reverse items))))

    (define (read-text text file)
      (read-all (make-source file text) 0 '()))

    (define (read-file path)
      (read-text (call-with-input-file path
                   (lambda (port)
                     (let loop ((chunks '()))
                       (let ((chunk (read-string 65536 port)))
                         (if (eof-object? chunk)
                             (apply string-append (reverse chunks))
                             (loop (cons chunk chunks)))))))
                 path))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-read)
    (import
     (lofi testing))
    (begin
      (define (test-read)
        (expect (map syntax->datum
                     (read-text "(define [f x] (+ x 1.5)) ; note\n\"a\\nb\" #\\a #\\space #| #| |# |# #t #;(skip) 'x" "t"))
                '((define (f x) (+ x 1.5)) "a\nb" #\a #\space #t (quote x)))
        (let ((forms (read-text "\n  (a\n   b)" "t.sld")))
          (expect (loc->string (syntax-loc (car forms))) "t.sld:2:3")
          (expect (loc->string (syntax-loc (cadr (Form-items (car forms))))) "t.sld:3:4"))
        (expect (guard (failure (#t (error-object-message failure))) (read-text "(a" "t"))
                "t:1:1: unclosed list"))))
   (else)))
