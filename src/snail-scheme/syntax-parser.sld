(define-library (snail-scheme syntax-parser)
  (export
   parse-file
   file
   expr
   s-sequence
   s-terminal
   symbol-or-number
   boolean-expr
   char-expr
   s-pipe-symbol-terminal
   s-string-terminal
   s-bytevector-terminal
   s-quote
   number-literal?
   char-literal?
   improper-tail
   hexadecimal-integer
   hexadecimal-digit
   decimal-integer
   decimal-digit
   whitespace
   whitespace-char
   intertoken-space
   line-comment
   block-comment
   datum-comment)

  (import
   (scheme base)
   (only (scheme char) string-ci=?)
   (snail-scheme common)
   (snail-scheme reader)
   (snail-scheme parser)
   (snail-scheme syntax))

  (begin
    ;;; Public API

    (define (parse-file reader)
      (let ((parse-result ((file) reader)))
        (if (parse-result-ok? parse-result)
            (parse-result-value parse-result)
            (error "parse failed" (reader-filename reader) parse-result))))

    ;;; Nonterminals

    ;; Files and expression dispatch

    (define (file)
      (pmap (tuple (repeat (expr)) (intertoken-space) (eof)) first))

    (define (expr)
      (chain
       (lambda (_) (intertoken-space))
       (lambda (_) (choice (s-sequence) (s-quote) (s-terminal)))))

    (define (s-terminal)
      (choice (s-pipe-symbol-terminal) (s-string-terminal) (s-bytevector-terminal)
              (char-expr) (boolean-expr) (symbol-or-number)))

    ;; Lists and vectors

    (define (s-sequence)
      (choice
       (proper-sequence (tag "#"))
       (proper-sequence (return '()))
       (improper-list)))

    (define (proper-sequence prefix)
      (pmap
       (tuple (location) prefix
              (choice (fenced-elements #\( #\) (expr))
                      (fenced-elements #\[ #\] (expr))
                      (fenced-elements #\{ #\} (expr))))
       (lambda (t) (make-list-syntax (third t) '() (first t) (second t)))))

    (define (improper-list)
      (choice (fenced-improper-list #\( #\))
              (fenced-improper-list #\[ #\])
              (fenced-improper-list #\{ #\})))

    (define (fenced-elements open close element)
      (pmap (tuple (char open) (repeat element) (intertoken-space) (char close)) second))

    (define (fenced-improper-list open close)
      (pmap (tuple (location) (char open) (repeat-at-least-once (expr))
                   (improper-tail) (intertoken-space) (char close))
            (lambda (t) (make-list-syntax (third t) (fourth t) (first t) '()))))

    (define (improper-tail)
      (chain
       (lambda (_)
         (tuple (intertoken-space)
                (char #\.)
                ;; A standalone dot ends at a delimiter or EOF.
                (not-followed-by (char-if char-bare-atom?))))
       (lambda (_) (expr))))

    ;; Quote abbreviations

    (define (s-quote)
      (pmap
       (tuple (location)
              (choice (tag-val "'" 'quote) (tag-val "`" 'quasiquote)
                      (tag-val ",@" 'unquote-splicing) (tag-val "," 'unquote))
              (expr))
       (lambda (t)
         (make-list-syntax
          (list (make-atom-syntax (second t) (first t)) (third t)) '() (first t) '()))))

    ;; Atomic literals

    (define (s-pipe-symbol-terminal)
      (pmap (tuple (location) (delimited-text #\| char-quoted-identifier?))
            (lambda (t) (make-atom-syntax (string->symbol (second t)) (first t)))))

    (define (s-string-terminal)
      (pmap (tuple (location) (delimited-text #\" char-string-literal?))
            (lambda (t) (make-atom-syntax (second t) (first t)))))

    (define (s-bytevector-terminal)
      (pmap
       (tuple (location) (tag-ci "#u8")
              (choice (fenced-elements #\( #\) (byte-element))
                      (fenced-elements #\[ #\] (byte-element))
                      (fenced-elements #\{ #\} (byte-element))))
       (lambda (t) (make-atom-syntax (apply bytevector (third t)) (first t)))))

    (define (byte-element)
      (chain
       (lambda (_) (intertoken-space))
       (lambda (_) (symbol-or-number))
       (lambda (stx)
         (let ((value (atom-syntax-value stx)))
           (if (and (exact-integer? value) (<= 0 value 255))
               (return value)
               (fail))))))

    (define (char-expr)
      (chain
       (lambda (_)
         (tuple (location)
                ;; The first character after #\ may itself be a delimiter.
                (capture (tuple (tag "#\\") (char-if char?)
                                (repeat (char-if char-bare-atom?))))))
       (lambda (t)
         (if (char-literal? (second t))
             (return (make-atom-syntax (literal-value (character-literal) (second t)) (first t)))
             (fail)))))

    (define (boolean-expr)
      (chain
       (lambda (_) (tuple (location) (bare-spelling)))
       (lambda (t)
         (let ((text (second t)) (loc (first t)))
           (cond
            ((or (string-ci=? text "#t") (string-ci=? text "#true"))
             (return (make-atom-syntax #t loc)))
            ((or (string-ci=? text "#f") (string-ci=? text "#false"))
             (return (make-atom-syntax #f loc)))
            (else (fail)))))))

    ;; Read the whole spelling before selecting its meaning. No surrounding
    ;; whitespace is consumed: hello#t and 12abc cannot split into smaller atoms.
    (define (symbol-or-number)
      (chain
       (lambda (_) (tuple (location) (bare-spelling)))
       (lambda (t)
         (let ((text (second t)) (loc (first t)))
           (cond
            ((number-literal? text)
             (let ((number (string->number text)))
               (if number (return (make-atom-syntax number loc)) (fail))))
            ((symbol-literal? text) (return (make-atom-syntax (string->symbol text) loc)))
            (else (fail)))))))

    ;;; Terminals

    ;; Complete literal spellings

    (define (number-literal? text)
      (and (string? text) (parse-result-ok? (literal-result (numeric-spelling) text))))

    (define (char-literal? text)
      (and (string? text) (parse-result-ok? (literal-result (character-literal) text))))

    (define (symbol-literal? text)
      (and (string? text) (parse-result-ok? (literal-result (identifier) text))))

    (define (literal-value parser text)
      (parse-result-value (literal-result parser text)))

    ;; Literal predicates run on complete strings, not on the enclosing reader.
    ;; EOF here is the end of that isolated spelling, never a token-boundary peek.
    (define (literal-result parser text)
      ((pmap (tuple parser (eof)) first) (string->reader "<literal>" text)))

    ;; Delimited text and characters

    (define (delimited-text delimiter ordinary?)
      (pmap (tuple (char delimiter)
                   (repeat (choice (escaped-character) (char-if ordinary?)))
                   (char delimiter))
            (lambda (t) (list->string (second t)))))

    (define (escaped-character)
      (choice
       (tag-val "\\a" #\alarm) (tag-val "\\b" #\backspace)
       (tag-val "\\t" #\tab) (tag-val "\\n" #\newline) (tag-val "\\r" #\return)
       (tag-val "\\\"" #\") (tag-val "\\\\" #\\) (tag-val "\\|" #\|)
       (chain
        (lambda (_) (tuple (tag "\\x") (hexadecimal-integer) (char #\;)))
        (lambda (t) (unicode-character (second t))))))

    (define (character-literal)
      (choice
       (tag-val "#\\alarm" #\alarm) (tag-val "#\\backspace" #\backspace)
       (tag-val "#\\delete" #\delete) (tag-val "#\\escape" #\escape)
       (tag-val "#\\newline" #\newline) (tag-val "#\\null" #\null)
       (tag-val "#\\return" #\return) (tag-val "#\\space" #\space) (tag-val "#\\tab" #\tab)
       (chain
        (lambda (_) (tuple (tag "#\\x") (hexadecimal-integer)))
        (lambda (t) (unicode-character (second t))))
       (pmap (tuple (tag "#\\") (char-if char?)) second)))

    (define (unicode-character codepoint)
      (if (and (<= 0 codepoint #x10ffff) (not (<= #xd800 codepoint #xdfff)))
          (return (integer->char codepoint))
          (fail)))

    ;; Identifier spellings

    (define (bare-spelling)
      (capture
       (tuple (char-if char-bare-atom-initial?) (repeat (char-if char-bare-atom?)))))

    ;; identifier <- initial subsequent* / peculiar-identifier
    (define (identifier)
      (tuple
       (optional (tag "#%-"))
       (choice
        (tuple (char-if char-identifier-initial?) (repeat (char-if char-identifier-subsequent?)))
        (peculiar-identifier))))

    (define (peculiar-identifier)
      (choice
       (tuple (char-if char-sign?)
              (char-if char-sign-subsequent?)
              (repeat (char-if char-identifier-subsequent?)))
       (tuple (char-if char-sign?) (char #\.)
              (char-if char-dot-subsequent?)
              (repeat (char-if char-identifier-subsequent?)))
       (tuple (char #\.) (char-if char-dot-subsequent?)
              (repeat (char-if char-identifier-subsequent?)))
       (char-if char-sign?)))

    ;; Numeric spellings

    (define (numeric-spelling)
      (choice
       (radix-number "#b" char-binary-digit? #f)
       (radix-number "#o" char-octal-digit? #f)
       (radix-number "#x" char-hexadecimal-digit? #f)
       (radix-number "#d" char-decimal-digit? #t)))

    (define (radix-number radix digit? decimal?)
      (tuple (if decimal? (optional (number-prefix radix)) (number-prefix radix))
             (complex-number digit? decimal?)))

    ;; prefix <- radix exactness? / exactness radix?
    ;; Only decimal may omit the radix marker.
    (define (number-prefix radix)
      (choice
       (tuple (tag-ci radix) (optional (exactness)))
       (tuple (exactness)
              (if (equal? radix "#d") (optional (tag-ci radix)) (tag-ci radix)))))

    ;; Longer alternatives precede their real-number prefixes in PEG choice.
    (define (complex-number digit? decimal?)
      (choice
       (tuple (real-number digit? decimal?) (char #\@) (real-number digit? decimal?))
       (tuple (real-number digit? decimal?) (imaginary-number digit? decimal?))
       (imaginary-number digit? decimal?)
       (real-number digit? decimal?)))

    (define (imaginary-number digit? decimal?)
      (tuple (char-if char-sign?)
             (optional (choice (unsigned-special-real) (unsigned-real digit? decimal?)))
             (tag-ci "i")))

    (define (real-number digit? decimal?)
      (choice
       (tuple (char-if char-sign?) (unsigned-special-real))
       (tuple (optional (char-if char-sign?)) (unsigned-real digit? decimal?))))

    (define (unsigned-special-real)
      (choice (tag-ci "inf.0") (tag-ci "nan.0")))

    (define (unsigned-real digit? decimal?)
      (choice
       (tuple (repeat-at-least-once (char-if digit?))
              (char #\/)
              (repeat-at-least-once (char-if digit?)))
       (if decimal?
           (decimal-number)
           (repeat-at-least-once (char-if digit?)))))

    ;; decimal <- (digit+ "." digit* / "." digit+ / digit+) exponent?
    (define (decimal-number)
      (tuple
       (choice
        (tuple (repeat-at-least-once (decimal-digit)) (char #\.) (repeat (decimal-digit)))
        (tuple (char #\.) (repeat-at-least-once (decimal-digit)))
        (repeat-at-least-once (decimal-digit)))
       (optional (exponent))))

    (define (exponent)
      (tuple (tag-ci "e")
             (optional (char-if char-sign?))
             (repeat-at-least-once (decimal-digit))))

    (define (exactness)
      (choice (tag-ci "#e") (tag-ci "#i")))

    (define (hexadecimal-integer)
      (pmap (repeat-at-least-once (hexadecimal-digit))
            (lambda (digits) (string->number (list->string digits) 16))))

    (define (decimal-integer)
      (pmap (repeat-at-least-once (decimal-digit))
            (lambda (digits) (string->number (list->string digits) 10))))

    (define (hexadecimal-digit)
      (char-if char-hexadecimal-digit?))

    (define (decimal-digit)
      (char-if char-decimal-digit?))

    ;; Whitespace and comments

    (define (intertoken-space)
      (discard
       (repeat
        (choice
         ;; Require progress before repeating the nullable whitespace rule.
         (tuple (whitespace-char) (whitespace))
         (line-comment)
         (block-comment)
         (datum-comment)))))

    (define (whitespace)
      (discard (repeat (whitespace-char))))

    (define (whitespace-char)
      (discard (char-if char-intertoken-space?)))

    (define (line-comment)
      (discard
       (tuple (char #\;)
              (repeat (char-if char-line-comment?)))))

    ;; block-comment <- "#|" (block-comment / !("#|" / "|#") .)* "|#"
    (define (block-comment)
      (discard
       (chain
        (lambda (_) (tag "#|"))
        (lambda (_)
          (tuple (repeat (block-comment-element)) (tag "|#"))))))

    (define (block-comment-element)
      (choice
       (block-comment)
       (tuple (not-followed-by (choice (tag "#|") (tag "|#")))
              (char-if char?))))

    (define (datum-comment)
      (discard
       (chain
        (lambda (_) (tag "#;"))
        (lambda (_) (expr)))))
    ))
