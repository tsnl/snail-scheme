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
   list-syntax-prefix
   <atom-syntax>
   make-atom-syntax
   atom-syntax?
   atom-syntax-value
   atom-syntax-loc

   ;; Syntax grammar
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
   (snail-scheme parser))

  (begin
    ;;;
    ;;; Syntax types
    ;;;

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
       loc ; location of the prefix or opening fence
       prefix) ; () for lists, "#" for vectors, or "#u8" for bytevectors
      list-syntax?
      (elements list-syntax-elements)
      (improper-tail list-syntax-improper-tail)
      (loc list-syntax-loc)
      (prefix list-syntax-prefix))

    (define-record-type <atom-syntax>
      (make-atom-syntax
       value ; decoded terminal value
       loc) ; loc indicating the start of this syntax object
      atom-syntax?
      (value atom-syntax-value)
      (loc atom-syntax-loc))

    ;;;
    ;;; Parser
    ;;;

    ;; Whitespace parsers
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

    ;; Expression parsers
    ;;

    (define (file)
      (pmap (tuple (repeat (expr)) (intertoken-space) (eof)) first))

    (define (expr)
      (chain
       (lambda (_) (intertoken-space))
       (lambda (_) (choice (s-sequence) (s-quote) (s-terminal)))))

    (define (s-sequence)
      (choice
       (proper-sequence (pmap (tag-ci "#u8") (lambda (_) "#u8")))
       (proper-sequence (tag "#"))
       (proper-sequence (return '()))
       (improper-list)))

    (define (proper-sequence prefix)
      (chain
       (lambda (_)
         (tuple (location)
		prefix
                (choice (fenced-elements #\( #\))
                        (fenced-elements #\[ #\])
                        (fenced-elements #\{ #\}))))
       (lambda (t)
         (let ((loc (first t))
	       (prefix (second t))
	       (elements (third t)))
           (if (or (null? prefix) (equal? prefix "#") (every? byte-syntax? elements))
               (return (make-list-syntax elements '() loc prefix))
               (fail))))))

    (define (fenced-elements open close)
      (pmap (tuple (char open) (repeat (expr)) (intertoken-space) (char close)) second))

    (define (improper-list)
      (choice (fenced-improper-list #\( #\))
              (fenced-improper-list #\[ #\])
              (fenced-improper-list #\{ #\})))

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

    (define (s-terminal)
      (choice (s-pipe-symbol-terminal) (s-string-terminal)
              (char-expr) (boolean-expr) (symbol-or-number)))

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

    (define (bare-spelling)
      (capture
       (tuple (char-if char-bare-atom-initial?) (repeat (char-if char-bare-atom?)))))

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

    (define (s-pipe-symbol-terminal)
      (pmap (tuple (location) (delimited-text #\| char-quoted-identifier?))
            (lambda (t) (make-atom-syntax (string->symbol (second t)) (first t)))))

    (define (s-string-terminal)
      (pmap (tuple (location) (delimited-text #\" char-string-literal?))
            (lambda (t) (make-atom-syntax (second t) (first t)))))

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

    (define (byte-syntax? stx)
      (and (atom-syntax? stx)
           (let
	       ((value (atom-syntax-value stx)))
             (and
	      (exact-integer? value)
	      (<= 0 value 255)))))

    (define (s-quote)
      (pmap
       (tuple (location)
              (choice (tag-val "'" 'quote) (tag-val "`" 'quasiquote)
                      (tag-val ",@" 'unquote-splicing) (tag-val "," 'unquote))
              (expr))
       (lambda (t)
         (make-list-syntax
          (list (make-atom-syntax (second t) (first t)) (third t)) '() (first t) '()))))

    ;; Literal predicates run on complete strings, not on the enclosing reader.
    ;; EOF here is the end of that isolated spelling, never a token-boundary peek.
    (define (literal-result parser text)
      ((pmap (tuple parser (eof)) first) (string->reader "<literal>" text)))

    (define (literal-value parser text)
      (parse-result-value (literal-result parser text)))

    (define (number-literal? text)
      (and (string? text) (parse-result-ok? (literal-result (numeric-spelling) text))))

    (define (char-literal? text)
      (and (string? text) (parse-result-ok? (literal-result (character-literal) text))))

    (define (symbol-literal? text)
      (and (string? text) (parse-result-ok? (literal-result (identifier) text))))

    (define (numeric-spelling)
      (choice
       (radix-number "#b" char-binary-digit? #f)
       (radix-number "#o" char-octal-digit? #f)
       (radix-number "#x" char-hexadecimal-digit? #f)
       (radix-number "#d" char-decimal-digit? #t)))

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

    (define (unicode-character codepoint)
      (if (and (<= 0 codepoint #x10ffff) (not (<= #xd800 codepoint #xdfff)))
          (return (integer->char codepoint))
          (fail)))

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

    ;; Public API
    ;;

    (define (parse-file reader)
      (let ((parse-result ((file) reader)))
        (if (parse-result-ok? parse-result)
            (parse-result-value parse-result)
            (error "parse failed" (reader-filename reader) parse-result))))

    ;;;
    ;;; Syntax pattern, match, and rules
    ;;;

    (define-record-type <match-result>
      (make-match-result
       success?     ; boolean indicating whether the match succeeded
       groups)      ; list of match group objects, always `null` if not `success?`.
      match-result?
      (success? match-result-success?)
      (match-groups match-result-groups))
    
    (define-record-type <match-group>
      (make-match-group
       singleton?   ; boolean indicating whether the match is a singleton or an ellipsis match.
       name         ; the name of the pattern variable used to match this group
       data)        ; the matched value if a singleton, a list of matched values otherwise.
      match-group?
      (singleton? match-group-singleton?)
      (name match-group-name)
      (data match-group-data))

    (define-record-type <syntax-pattern-dispatch-result>
      (make-syntax-pattern-dispatch-result
       success?     ; boolean indicating whether the dispatch was successful on any of the patterns provided
       returned)    ; the callback return value if success?, otherwise null
      syntax-pattern-dispatch-result?
      (success? syntax-pattern-dispatch-result-success?)
      (returned syntax-pattern-dispatch-result-returned))

    ;; Check that a datum is a syntax pattern according to the R7RS spec.
    ;;  pattern
    ;;    : <identifier>
    ;;    | <constant>
    ;;    | (<pattern> ...)
    ;;    | (<pattern> <pattern> ... . <pattern>)
    ;;    | (<pattern> ... <pattern> <ellipsis> <pattern> ...)
    ;;    | (<pattern> ... <pattern> <ellipsis> <pattern> ... . <pattern>)
    ;;    | #(<pattern> ...)
    ;;    | #(<pattern> ... <pattern> <ellipsis> <pattern> ...)
    ;; Where
    ;;  ... => match preceding pattern 0 or more times
    (define (pattern? it)
      (let ((non-symbol-literal?
	     (lambda (it) (or (number? it) (char? it) (string? it)))))
      (or
       (symbol? it)
       (non-symbol-literal? it)
       (and
	(list? it)
	(or
	 (every? pattern? it)
	 ; TODO: pick up from here
	 )))))
    
    ;; syntax-pattern takes a list of (pattern . callback) datums and
    ;; returns a closure that matches syntax and dispatches the
    ;; appropriate callback with the `<match-result>`.
    ;;
    ;; Returns a syntax-pattern-dispatch-result
    ;;
    ;; Each argument passed to the lambda is a `<match-group>` instance.
    ;;
    ;; `pattern` is anything that would be provided to `syntax-rules`.
    ;;
    ;; Like syntax-rules, we also take in
    ;; - `ellipsis`: a token to use in lieu of the `...` literal
    ;; - `literals`: a list of symbols to match literally instead of as pattern variables
    (define (syntax-pattern ellipsis literals pattern-callback-pairs)
      (lambda (scrutinee)
	(let recur ((pattern-callback-pairs pattern-callback-pairs))
	  (if (null? pattern-callback-pairs)
	      (make-syntax-pattern-dispatch-result #f '())  ; no pattern matched
	  (let*
	      ((head-pattern-callback-pair (car pattern-callback-pairs))
	       (pattern (car head-pattern-callback-pair))
	       (callback (cdr head-pattern-callback-pair)))
	    (begin
	      (assert (procedure? callback))
	      (assert (pattern? pattern))
	      (dispatch-result (try-dispatch-syntax-pattern-arm ellipsis literals pattern callback scrutinee))
	  )
      ))

    (define (try-dispatch-syntax-pattern-arm ellipsis literals pattern callback scrutinee)
      (let ((match-result (match-syntax-pattern-arm ellipsis literals pattern scrutinee)))
	(if (match-result-success? match-result)
	    (make-syntax-pattern-dispatch-result #t (callback match-result))
	    (make-syntax-pattern-dispatch-result #f '()))))

    ;; `match-syntax-pattern-arm` returns a <match-result> if the 
    (define (match-syntax-pattern-arm ellipsis literals pattern scrutinee)
      ())
    
    ))
