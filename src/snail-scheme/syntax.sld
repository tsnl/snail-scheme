(define-library (snail-scheme syntax)
  (export
   ;; Syntax records
   syntax?
   syntax-loc
   <list-syntax>
   make-list-syntax
   list-syntax?
   list-syntax-elements
   list-syntax-improper-tail
   list-syntax-loc
   <atom-syntax>
   make-atom-syntax
   atom-syntax?
   atom-syntax-value
   atom-syntax-loc

   ;; Language parsers
   parse-file
   file
   expr
   list-expr
   char-expr
   string-expr
   string-expr-element
   boolean-expr
   number-expr
   identifier-expr
   quote-expr
   left-fender
   right-fender
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
   datum-comment
   token-end)

  (import
   (scheme base)
   (snail-scheme common)
   (snail-scheme reader)
   (snail-scheme parser))

  (begin
    ;;
    ;; syntax
    ;;

    (define (syntax? obj)
      (or
       (list-syntax? obj)
       (atom-syntax? obj)))

    (define (syntax-loc stx)
      (cond
       ((list-syntax? stx)
        (list-syntax-loc stx))
       ((atom-syntax? stx)
        (atom-syntax-loc stx))
       (else
        (error "syntax-loc expected syntax object" stx))))

    (define-record-type <list-syntax>
      (make-list-syntax
       elements ; list of syntax objects
       improper-tail ; null or a syntax object representing the improper tail
       loc) ; loc indicating the start of this list syntax object
      list-syntax?
      (elements list-syntax-elements)
      (improper-tail list-syntax-improper-tail)
      (loc list-syntax-loc))

    (define-record-type <atom-syntax>
      (make-atom-syntax
       value ; value of this atom: number? or char? or string? or symbol?
       loc) ; loc indicating the start of this syntax object
      atom-syntax?
      (value atom-syntax-value)
      (loc atom-syntax-loc))

    ;;
    ;; Whitespace and comments
    ;;

    (define (whitespace)
      (discard (repeat (whitespace-char))))

    (define (whitespace-char)
      (discard (char-if char-intertoken-space?)))

    (define (intertoken-space)
      (discard
       (repeat
        (choice
         ;; Require progress before repeating the nullable whitespace rule.
         (tuple (whitespace-char) (whitespace))
         (line-comment)
         (block-comment)
         (datum-comment)))))

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

    ;;
    ;; Expression parsers
    ;;

    (define (file)
      (pmap (tuple (repeat (expr)) (intertoken-space) (eof)) first))

    (define (expr)
      (chain
       (lambda (_) (intertoken-space))
       (lambda (_)
         (choice
          (list-expr)
          (char-expr)
          (string-expr)
          (boolean-expr)
          (number-expr)
          (identifier-expr)
          (quote-expr)))))

    (define (list-expr)
      (chain
       (lambda (_)
         (tuple
          (location)
          (left-fender)
          (repeat (expr))
          (improper-tail)
          (intertoken-space)
          (right-fender)))
       (lambda (t)
         (let ((loc (first t))
               (elements (third t))
               (opt-tail (fourth t)))
           (if (and (null? elements) (not (null? opt-tail)))
               (fail)
               (return (make-list-syntax elements opt-tail loc)))))))

    (define (char-expr)
      (pmap
       (tuple
        (location)
        (choice
         ;; Standard special characters
         (tag-val "#\\alarm" #\alarm)
         (tag-val "#\\backspace" #\backspace)
         (tag-val "#\\delete" #\delete)
         (tag-val "#\\escape" #\escape)
         (tag-val "#\\newline" #\newline)
         (tag-val "#\\null" #\null)
         (tag-val "#\\return" #\return)
         (tag-val "#\\space" #\space)
         (tag-val "#\\tab" #\tab)

         ;; #\xHHHH...
         (chain
          (lambda (_) (tuple (tag "#\\x") (hexadecimal-integer)))
          (lambda (t) (unicode-character (second t))))

         ;; Otherwise, consume the first character after #\
         (pmap (tuple (tag "#\\") (char-if char?)) second))
        (token-end))
       (lambda (t)
         (let ((loc (first t))
               (chr (second t)))
           (make-atom-syntax chr loc)))))

    (define (string-expr)
      (pmap
       (tuple
        (location)
        (discard (char #\"))
        (repeat (string-expr-element))
        (discard (char #\")))
       (lambda (t)
         (let ((loc (first t))
               (elements (third t)))
           (make-atom-syntax (list->string elements) loc)))))

    (define (string-expr-element)
      (choice
       (tag-val "\\a" #\alarm)
       (tag-val "\\b" #\backspace)
       (tag-val "\\t" #\tab)
       (tag-val "\\n" #\newline)
       (tag-val "\\r" #\return)
       (tag-val "\\\"" #\")
       (tag-val "\\\\" #\\)
       ;; TODO: support `\` as a line delimiter

       ;; #\x{HHHH...};
       ;; note the trailing semicolon
       (chain
        (lambda (_) (tuple (tag "\\x") (hexadecimal-integer) (tag ";")))
        (lambda (t) (unicode-character (second t))))

       ;; A backslash must introduce a supported escape.
       (char-if char-string-literal?)))

    (define (unicode-character codepoint)
      (if (and (<= 0 codepoint #x10ffff)
               (not (<= #xd800 codepoint #xdfff)))
          (return (integer->char codepoint))
          (fail)))

    ;; Non-self-delimiting tokens end only at a delimiter or EOF.
    ;; This is an assertion in the grammar; it leaves the delimiter untouched.
    (define (token-end)
      (discard (lookahead (choice (eof) (char-if char-delimiter?)))))

    (define (boolean-expr)
      (pmap
       (tuple (location)
              (choice
               (pmap (choice (tag-ci "#true") (tag-ci "#t")) (lambda (_) #t))
               (pmap (choice (tag-ci "#false") (tag-ci "#f")) (lambda (_) #f)))
              (token-end))
       (lambda (t) (make-atom-syntax (second t) (first t)))))

    ;; The numeric grammar recognizes the spelling before conversion. The host
    ;; supplies numeric representation/precision, not the accepted lexical syntax.
    (define (number-expr)
      (chain
       (lambda (_) (tuple (location) (number-literal)))
       (lambda (t)
         (let ((number (string->number (second t))))
           ;; A grammatical number may be unrepresentable (for example #e1/0).
           (if number
               (return (make-atom-syntax number (first t)))
               (fail))))))

    (define (number-literal)
      (pmap
       (tuple
        (capture
         (choice
          (radix-number "#b" char-binary-digit? #f)
          (radix-number "#o" char-octal-digit? #f)
          (radix-number "#x" char-hexadecimal-digit? #f)
          (radix-number "#d" char-decimal-digit? #t)))
        (token-end))
       first))

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

    (define (exactness)
      (choice (tag-ci "#e") (tag-ci "#i")))

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

    (define (identifier-expr)
      ;; TODO: parse `|`...`|` identifiers.
      (pmap
       (tuple (location)
              ;; Numeric spellings such as +i and +inf.0 are not identifiers.
              (not-followed-by (number-literal))
              (capture (identifier))
              (token-end))
       (lambda (t) (make-atom-syntax (string->symbol (third t)) (first t)))))

    ;; identifier <- initial subsequent* / peculiar-identifier
    (define (identifier)
      (choice
       (tuple (char-if char-identifier-initial?) (repeat (char-if char-identifier-subsequent?)))
       (peculiar-identifier)))

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

    (define (quote-expr)
      (pmap
       (tuple
        (location)
        (choice (tag-val "'" 'quote)
                (tag-val "`" 'quasiquote)
                (tag-val ",@" 'unquote-splicing)
                (tag-val "," 'unquote))
        (expr))
       (lambda (t)
         (let ((loc (first t)))
           (make-list-syntax
            (list (make-atom-syntax (second t) loc) (third t))
            '()
            loc)))))

    (define (left-fender)
      (discard (char #\()))

    (define (right-fender)
      (discard (char #\))))

    (define (improper-tail)
      (optional
       (chain
        (lambda (_) (tuple (intertoken-space) (char #\.) (token-end)))
        (lambda (_) (expr)))))

    (define (hexadecimal-integer)
      (pmap (repeat-at-least-once (hexadecimal-digit))
            (lambda (digits) (string->number (list->string digits) 16))))

    (define (hexadecimal-digit)
      (char-if char-hexadecimal-digit?))

    (define (decimal-integer)
      (pmap (repeat-at-least-once (decimal-digit))
            (lambda (digits) (string->number (list->string digits) 10))))

    (define (decimal-digit)
      (char-if char-decimal-digit?))

    ;;
    ;; Public API
    ;;

    (define (parse-file reader)
      (let ((parse-result ((file) reader)))
        (if (parse-result-ok? parse-result)
            (parse-result-value parse-result)
            (error "parse failed" (reader-filename reader) parse-result))))))
