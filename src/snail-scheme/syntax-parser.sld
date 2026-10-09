(define-library (snail-scheme syntax-parser)
  (export
   s-file
   s-expr
   s-atom

   ;; Temporary exports for the external test suite.
   s-list
   s-vector
   s-number
   s-symbol
   s-boolean
   s-char
   s-pipe-symbol
   s-string
   s-bytevector
   s-quote
   number-literal?
   char-literal?
   symbol-literal?
   improper-tail
   hexadecimal-integer
   hexadecimal-digit
   decimal-integer
   decimal-digit
   whitespace
   whitespace-char
   line-comment
   block-comment
   datum-comment)

  (import
   (scheme base)
   (snail-scheme common)
   (snail-scheme reader)
   (snail-scheme parser)
   (snail-scheme syntax))

  (begin
    ;;; Public API
    ;;;

    (define (s-file)
      (pmap
       (named-tuple
        `(forms . ,(repeat (s-expr)))
        `(_ . ,(optional (intertoken-space)))
        `(_ . ,(eof)))
       (lambda (fields) (cdr (assq 'forms fields)))))

    (define (s-expr)
      (chain
       (optional (intertoken-space))
       (lambda (_)
         (choice
          (s-list)
          (s-vector)
          (s-quote)
          (s-atom)))))

    (define (s-atom)
      (choice
       (s-pipe-symbol)
       (s-string)
       (s-bytevector)
       (s-char)
       (s-boolean)
       (s-number)
       (s-symbol)))

    ;;; Implementation
    ;;;

    ;; Lists and vectors

    (define (s-list)
      (choice
       (pmap
        (named-tuple
         `(loc . ,(location))
         `(elements . ,(choice
                        (fenced-elements #\( #\) (s-expr))
                        (fenced-elements #\[ #\] (s-expr))
                        (fenced-elements #\{ #\} (s-expr)))))
        (lambda (fields)
          (make-list-syntax (cdr (assq 'elements fields)) '() (cdr (assq 'loc fields)) '())))
       (improper-list)))

    (define (s-vector)
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(prefix . ,(tag "#"))
        `(elements . ,(choice
                       (fenced-elements #\( #\) (s-expr))
                       (fenced-elements #\[ #\] (s-expr))
                       (fenced-elements #\{ #\} (s-expr)))))
       (lambda (fields)
         (make-list-syntax (cdr (assq 'elements fields)) '() (cdr (assq 'loc fields))
                           (cdr (assq 'prefix fields))))))

    (define (improper-list)
      (choice
       (fenced-improper-list #\( #\))
       (fenced-improper-list #\[ #\])
       (fenced-improper-list #\{ #\})))

    (define (fenced-elements open close element)
      (pmap
       (named-tuple
        `(_ . ,(char open))
        `(elements . ,(repeat element))
        `(_ . ,(optional (intertoken-space)))
        `(_ . ,(char close)))
       (lambda (fields) (cdr (assq 'elements fields)))))

    (define (fenced-improper-list open close)
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(_ . ,(char open))
        `(elements . ,(repeat-at-least-once (s-expr)))
        `(tail . ,(improper-tail))
        `(_ . ,(optional (intertoken-space)))
        `(_ . ,(char close)))
       (lambda (fields)
         (make-list-syntax (cdr (assq 'elements fields)) (cdr (assq 'tail fields))
                           (cdr (assq 'loc fields)) '()))))

    (define (improper-tail)
      (chain
       (tuple
        (optional (intertoken-space))
        (char #\.)
        (not-followed-by (char-if char-bare-atom?)))
       (lambda (_) (s-expr))))

    ;; Quote abbreviations

    (define (s-quote)
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(name . ,(choice
                   (tag-val "'" 'quote)
                   (tag-val "`" 'quasiquote)
                   (tag-val ",@" 'unquote-splicing)
                   (tag-val "," 'unquote)))
        `(value . ,(s-expr)))
       (lambda (fields)
         (let ((loc (cdr (assq 'loc fields))))
           (make-list-syntax
            (list (make-atom-syntax (cdr (assq 'name fields)) loc)
                  (cdr (assq 'value fields)))
            '() loc '())))))

    ;; Atomic literals

    (define (s-pipe-symbol)
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(_ . ,(char #\|))
        `(characters . ,(repeat
                         (choice
                          (escaped-character)
                          (char-if char-quoted-identifier?))))
        `(_ . ,(char #\|)))
       (lambda (fields)
         (make-atom-syntax (string->symbol (list->string (cdr (assq 'characters fields))))
                           (cdr (assq 'loc fields))))))

    (define (s-string)
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(value . ,(string-literal)))
       (lambda (fields)
         (make-atom-syntax (cdr (assq 'value fields)) (cdr (assq 'loc fields))))))

    (define (s-bytevector)
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(_ . ,(tag-ci "#u8"))
        `(bytes . ,(choice
                    (fenced-elements #\( #\) (byte-element))
                    (fenced-elements #\[ #\] (byte-element))
                    (fenced-elements #\{ #\} (byte-element)))))
       (lambda (fields)
         (make-atom-syntax (apply bytevector (cdr (assq 'bytes fields)))
                           (cdr (assq 'loc fields))))))

    (define (byte-element)
      (where
       (pmap
        (named-tuple
         `(_ . ,(optional (intertoken-space)))
         `(number . ,(s-number)))
        (lambda (fields) (atom-syntax-value (cdr (assq 'number fields)))))
       (lambda (value) (and (exact-integer? value) (<= 0 value 255)))))

    (define (s-char)
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(value . ,(character-literal))
        `(_ . ,(not-followed-by (char-if char-bare-atom?))))
       (lambda (fields)
         (make-atom-syntax (cdr (assq 'value fields)) (cdr (assq 'loc fields))))))

    (define (s-boolean)
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(value . ,(choice
                    (pmap
                     (choice
                      (tag-ci "#true")
                      (tag-ci "#t"))
                     (lambda (_) #t))
                    (pmap
                     (choice
                      (tag-ci "#false")
                      (tag-ci "#f"))
                     (lambda (_) #f))))
        `(_ . ,(not-followed-by (char-if char-bare-atom?))))
       (lambda (fields)
         (make-atom-syntax (cdr (assq 'value fields)) (cdr (assq 'loc fields))))))

    (define (s-number)
      (chain
       (named-tuple
        `(loc . ,(location))
        `(text . ,(numeric-spelling))
        `(_ . ,(not-followed-by (char-if char-bare-atom?))))
       (lambda (fields)
         (let ((number (string->number (cdr (assq 'text fields)))))
           (if number
               (return (make-atom-syntax number (cdr (assq 'loc fields))))
               (fail))))))

    (define (s-symbol)
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(text . ,(identifier))
        `(_ . ,(not-followed-by (char-if char-bare-atom?))))
       (lambda (fields)
         (make-atom-syntax (string->symbol (cdr (assq 'text fields)))
                           (cdr (assq 'loc fields))))))

    ;;; Terminals

    ;; Delimited text and characters

    (define (string-literal)
      (pmap
       (named-tuple
        `(_ . ,(char #\"))
        `(characters . ,(repeat
                         (choice
                          (escaped-character)
                          (char-if char-string-literal?))))
        `(_ . ,(char #\")))
       (lambda (fields) (list->string (cdr (assq 'characters fields))))))

    (define (escaped-character)
      (choice
       (tag-val "\\a" #\alarm)
       (tag-val "\\b" #\backspace)
       (tag-val "\\t" #\tab)
       (tag-val "\\n" #\newline)
       (tag-val "\\r" #\return)
       (tag-val "\\\"" #\")
       (tag-val "\\\\" #\\)
       (tag-val "\\|" #\|)
       (chain
        (named-tuple
         `(_ . ,(tag "\\x"))
         `(codepoint . ,(hexadecimal-integer))
         `(_ . ,(char #\;)))
        (lambda (fields) (unicode-character (cdr (assq 'codepoint fields)))))))

    (define (character-literal)
      (choice
       (tag-val "#\\alarm" #\alarm)
       (tag-val "#\\backspace" #\backspace)
       (tag-val "#\\delete" #\delete)
       (tag-val "#\\escape" #\escape)
       (tag-val "#\\newline" #\newline)
       (tag-val "#\\null" #\null)
       (tag-val "#\\return" #\return)
       (tag-val "#\\space" #\space)
       (tag-val "#\\tab" #\tab)
       (chain
        (named-tuple
         `(_ . ,(tag "#\\x"))
         `(codepoint . ,(hexadecimal-integer)))
        (lambda (fields) (unicode-character (cdr (assq 'codepoint fields)))))
       ;; The character after #\ may itself be a delimiter.
       (chain (tag "#\\") (lambda (_) (char-if char?)))))

    (define (unicode-character codepoint)
      (if (and (<= 0 codepoint #x10ffff) (not (<= #xd800 codepoint #xdfff)))
          (return (integer->char codepoint))
          (fail)))

    ;; Identifier spellings

    (define (identifier)
      (pmap
       (tuple
        ;; Numeric spellings such as +i and +inf.0 take precedence over identifiers.
        (not-followed-by
         (tuple
          (numeric-spelling)
          (not-followed-by (char-if char-bare-atom?))))
        (optional (tag "#%-"))
        (choice
         (tuple
          (char-if char-identifier-initial?)
          (repeat (char-if char-identifier-subsequent?)))
         (peculiar-identifier)))
       spelling->string))

    ;; R7RS identifiers beginning with +, -, or . need distinct initial rules.
    (define (peculiar-identifier)
      (choice
       (tuple
        (char-if char-sign?)
        (char-if char-sign-subsequent?)
        (repeat (char-if char-identifier-subsequent?)))
       (tuple
        (char-if char-sign?)
        (char #\.)
        (char-if char-dot-subsequent?)
        (repeat (char-if char-identifier-subsequent?)))
       (tuple
        (char #\.)
        (char-if char-dot-subsequent?)
        (repeat (char-if char-identifier-subsequent?)))
       (char-if char-sign?)))

    ;; Numeric spellings

    (define (numeric-spelling)
      (pmap
       (choice
        (radix-number "#b" char-binary-digit? #f)
        (radix-number "#o" char-octal-digit? #f)
        (radix-number "#x" char-hexadecimal-digit? #f)
        (radix-number "#d" char-decimal-digit? #t))
       spelling->string))

    (define (radix-number radix digit? decimal?)
      (tuple
       (if decimal? (optional (number-prefix radix)) (number-prefix radix))
       (complex-number digit? decimal?)))

    ;; prefix <- radix exactness? / exactness radix?
    ;; Only decimal may omit the radix marker.
    (define (number-prefix radix)
      (choice
       (tuple
        (tag-ci radix)
        (optional (exactness)))
       (tuple
        (exactness)
        (if (equal? radix "#d") (optional (tag-ci radix)) (tag-ci radix)))))

    ;; Longer alternatives precede their real-number prefixes in PEG choice.
    (define (complex-number digit? decimal?)
      (choice
       (tuple
        (real-number digit? decimal?)
        (char #\@)
        (real-number digit? decimal?))
       (tuple
        (real-number digit? decimal?)
        (imaginary-number digit? decimal?))
       (imaginary-number digit? decimal?)
       (real-number digit? decimal?)))

    (define (imaginary-number digit? decimal?)
      (tuple
       (char-if char-sign?)
       (optional
        (choice
         (unsigned-special-real)
         (unsigned-real digit? decimal?)))
       (tag-ci "i")))

    (define (real-number digit? decimal?)
      (choice
       (tuple
        (char-if char-sign?)
        (unsigned-special-real))
       (tuple
        (optional (char-if char-sign?))
        (unsigned-real digit? decimal?))))

    (define (unsigned-special-real)
      (choice
       (tag-ci "inf.0")
       (tag-ci "nan.0")))

    (define (unsigned-real digit? decimal?)
      (choice
       (tuple
        (repeat-at-least-once (char-if digit?))
        (char #\/)
        (repeat-at-least-once (char-if digit?)))
       (if decimal?
           (decimal-number)
           (repeat-at-least-once (char-if digit?)))))

    ;; decimal <- (digit+ "." digit* / "." digit+ / digit+) exponent?
    (define (decimal-number)
      (tuple
       (choice
        (tuple
         (repeat-at-least-once (decimal-digit))
         (char #\.)
         (repeat (decimal-digit)))
        (tuple
         (char #\.)
         (repeat-at-least-once (decimal-digit)))
        (repeat-at-least-once (decimal-digit)))
       (optional (exponent))))

    (define (exponent)
      (tuple
       (tag-ci "e")
       (optional (char-if char-sign?))
       (repeat-at-least-once (decimal-digit))))

    (define (exactness)
      (choice
       (tag-ci "#e")
       (tag-ci "#i")))

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

    ;; Join the character/string results nested by tuple and repeat.
    (define (spelling->string spelling)
      (cond
       ((char? spelling) (string spelling))
       ((string? spelling) spelling)
       (else (apply string-append (map spelling->string spelling)))))

    ;; Whitespace and comments

    (define (intertoken-space)
      (discard
       (repeat-at-least-once
        (choice
         ;; Require progress before repeating the nullable whitespace rule.
         (tuple
          (whitespace-char)
          (whitespace))
         (line-comment)
         (block-comment)
         (datum-comment)))))

    (define (whitespace)
      (discard (repeat (whitespace-char))))

    (define (whitespace-char)
      (discard (char-if char-intertoken-space?)))

    (define (line-comment)
      (discard
       (tuple
        (char #\;)
        (repeat (char-if char-line-comment?)))))

    ;; block-comment <- "#|" (block-comment / !("#|" / "|#") .)* "|#"
    (define (block-comment)
      (discard
       (chain
        (tag "#|")
        (lambda (_)
          (tuple
           (repeat (block-comment-element))
           (tag "|#"))))))

    (define (block-comment-element)
      (choice
       (block-comment)
       (tuple
        (not-followed-by
         (choice
          (tag "#|")
          (tag "|#")))
        (char-if char?))))

    (define (datum-comment)
      (discard (chain (tag "#;") (lambda (_) (s-expr)))))

    ;;; Literal predicates

    ;; These string APIs reuse the grammar; syntax rules never call them.
    (define (number-literal? text)
      (assert (string? text))
      (parse-result-ok?
       ((tuple
         (numeric-spelling)
         (eof))
        (string->reader "<number-literal>" text))))

    (define (char-literal? text)
      (assert (string? text))
      (parse-result-ok?
       ((tuple
         (character-literal)
         (eof))
        (string->reader "<char-literal>" text))))

    (define (symbol-literal? text)
      (assert (string? text))
      (parse-result-ok?
       ((tuple
         (identifier)
         (eof))
        (string->reader "<symbol-literal>" text))))
    ))
