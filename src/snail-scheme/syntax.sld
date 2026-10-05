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
   datum-comment

   ;; Syntax matching and dispatch
   pattern?
   syntax-pattern
   match-syntax-pattern-arm
   <match-result>
   make-match-result
   match-result?
   match-result-success?
   match-result-groups
   <match-group>
   make-match-group
   match-group?
   match-group-singleton?
   match-group-name
   match-group-data
   <syntax-pattern-dispatch-result>
   make-syntax-pattern-dispatch-result
   syntax-pattern-dispatch-result?
   syntax-pattern-dispatch-result-success?
   syntax-pattern-dispatch-result-returned)

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
      (groups match-result-groups))
    
    (define-record-type <match-group>
      (make-match-group
       singleton?   ; boolean indicating whether the match is a singleton or an ellipsis match.
       name         ; the name of the pattern variable used to match this group
       data)        ; syntax if singleton; otherwise lists nested once per ellipsis
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

    ;; Patterns are host datums; inputs and captures are located syntax objects.
    ;; Optional arguments to pattern? are the ellipsis symbol and literal list.
    ;; One repeated segment is allowed per list/vector level, with nesting.
    (define (pattern? it . options)
      (let ((ellipsis (if (pair? options) (car options) '...))
            (literals (if (and (pair? options) (pair? (cdr options))) (cadr options) '())))
        (and (<= (length options) 2)
             (symbol? ellipsis)
             (list? literals)
             (every? symbol? literals)
             (if (pattern-variables ellipsis literals it) #t #f))))

    (define (ellipsis? it ellipsis literals)
      (and (eq? it ellipsis) (not (memq it literals))))

    (define (repeated-pattern? pattern ellipsis literals)
      (and (pair? pattern) (pair? (cdr pattern))
           (ellipsis? (cadr pattern) ellipsis literals)))

    ;; Return variable names in traversal order, or #f for an invalid pattern.
    ;; The empty list is a valid result for a pattern without captures.
    (define (pattern-variables ellipsis literals pattern)
      (cond
       ((symbol? pattern)
        (cond ((memq pattern literals) '())
              ((ellipsis? pattern ellipsis literals) #f)
              ((eq? pattern '_) '())
              (else (list pattern))))
       ((pair? pattern) (sequence-pattern-variables ellipsis literals pattern #f))
       ((vector? pattern) (sequence-pattern-variables ellipsis literals (vector->list pattern) #f))
       ((or (null? pattern) (boolean? pattern) (number? pattern) (char? pattern)
            (string? pattern) (bytevector? pattern)) '())
       (else #f)))

    (define (sequence-pattern-variables ellipsis literals pattern repeated?)
      (cond
       ((not (pair? pattern)) (pattern-variables ellipsis literals pattern))
       ((repeated-pattern? pattern ellipsis literals)
        (and (not repeated?)
             (merge-pattern-variables
              (pattern-variables ellipsis literals (car pattern))
              (sequence-pattern-variables ellipsis literals (cddr pattern) #t))))
       (else
        (merge-pattern-variables
         (pattern-variables ellipsis literals (car pattern))
         (sequence-pattern-variables ellipsis literals (cdr pattern) repeated?)))))

    (define (merge-pattern-variables left right)
      (and left right
           (every? (lambda (name) (not (memq name right))) left)
           (append left right)))

    ;; Validate arms when constructing the dispatcher. The first matching arm
    ;; receives one match-result; even a callback returning #f is successful.
    ;; Match the head normally: use a literal head for forms, or _ to ignore it.
    (define (syntax-pattern ellipsis literals pattern-callback-pairs)
      (assert (symbol? ellipsis))
      (assert (and (list? literals) (every? symbol? literals)))
      (assert (list? pattern-callback-pairs))
      (for-each
       (lambda (arm)
         (assert (and (pair? arm) (procedure? (cdr arm))))
         (assert (pattern? (car arm) ellipsis literals)))
       pattern-callback-pairs)
      (lambda (scrutinee)
        (assert (syntax? scrutinee))
        (dispatch-syntax-pattern ellipsis literals pattern-callback-pairs scrutinee)))

    (define (dispatch-syntax-pattern ellipsis literals arms scrutinee)
      (if (null? arms)
          (make-syntax-pattern-dispatch-result #f '())
          (let ((result (try-dispatch-syntax-pattern-arm
                         ellipsis literals (caar arms) (cdar arms) scrutinee)))
            (if (syntax-pattern-dispatch-result-success? result)
                result
                (dispatch-syntax-pattern ellipsis literals (cdr arms) scrutinee)))))

    (define (try-dispatch-syntax-pattern-arm ellipsis literals pattern callback scrutinee)
      (let ((result (match-syntax-pattern ellipsis literals pattern scrutinee)))
        (if (match-result-success? result)
            (make-syntax-pattern-dispatch-result #t (callback result))
            (make-syntax-pattern-dispatch-result #f '()))))

    (define (match-syntax-pattern-arm ellipsis literals pattern scrutinee)
      (assert (pattern? pattern ellipsis literals))
      (assert (syntax? scrutinee))
      (match-syntax-pattern ellipsis literals pattern scrutinee))

    ;; View unprefixed syntax lists as pairs, including explicit dotted lists
    ;; such as (a . (b c)). Synthesized cdrs retain the containing list's location.
    (define (syntax-pair? stx)
      (and (list-syntax? stx) (null? (list-syntax-prefix stx))
           (pair? (list-syntax-elements stx))))

    (define (syntax-null? stx)
      (and (list-syntax? stx) (null? (list-syntax-prefix stx))
           (null? (list-syntax-elements stx)) (null? (list-syntax-improper-tail stx))))

    (define (syntax-cdr stx)
      (let ((rest (cdr (list-syntax-elements stx)))
            (tail (list-syntax-improper-tail stx)))
        (if (and (null? rest) (syntax? tail))
            tail
            (make-list-syntax rest tail (syntax-loc stx) '()))))

    (define (syntax-pair-count stx)
      (let loop ((stx stx) (count 0))
        (if (syntax-pair? stx)
            (loop (syntax-cdr stx) (+ count 1))
            count)))

    (define (pattern-pair-count pattern)
      (if (pair? pattern) (+ 1 (pattern-pair-count (cdr pattern))) 0))

    (define (match-syntax-pattern ellipsis literals pattern scrutinee)
      (let ((groups (match-pattern-groups ellipsis literals pattern scrutinee)))
        (make-match-result (if groups #t #f) (or groups '()))))

    ;; Internal matches return groups on success (possibly empty), or #f.
    (define (match-pattern-groups ellipsis literals pattern input)
      (cond
       ((symbol? pattern) (match-symbol-pattern literals pattern input))
       ((null? pattern) (and (syntax-null? input) '()))
       ((pair? pattern)
        (and (or (syntax-pair? input) (syntax-null? input))
             (match-sequence-pattern ellipsis literals pattern input)))
       ((vector? pattern) (match-vector-pattern ellipsis literals pattern input))
       ((bytevector? pattern) (match-bytevector-pattern pattern input))
       (else (and (atom-syntax? input) (equal? pattern (atom-syntax-value input)) '()))))

    (define (match-symbol-pattern literals pattern input)
      (cond
       ;; Binding-aware literal comparison belongs to the later scope pass.
       ((memq pattern literals)
        (and (atom-syntax? input) (eq? pattern (atom-syntax-value input)) '()))
       ((eq? pattern '_) '())
       (else (list (make-match-group #t pattern input)))))

    (define (match-sequence-pattern ellipsis literals pattern input)
      (cond
       ((not (pair? pattern)) (match-pattern-groups ellipsis literals pattern input))
       ((repeated-pattern? pattern ellipsis literals)
        (match-repeated-pattern ellipsis literals (car pattern) (cddr pattern) input))
       (else
        (and (syntax-pair? input)
             (combine-match-groups
              (match-pattern-groups ellipsis literals (car pattern) (car (list-syntax-elements input)))
              (match-sequence-pattern ellipsis literals (cdr pattern) (syntax-cdr input)))))))

    (define (match-repeated-pattern ellipsis literals item suffix input)
      (let ((count (- (syntax-pair-count input) (pattern-pair-count suffix)))
            (names (pattern-variables ellipsis literals item)))
        (and (>= count 0)
             (let loop ((remaining count) (input input) (iterations '()))
               (if (= remaining 0)
                   (combine-match-groups
                    (collect-repeated-match-groups names (reverse iterations))
                    (match-pattern-groups ellipsis literals suffix input))
                   (let ((groups (match-pattern-groups ellipsis literals item (car (list-syntax-elements input)))))
                     (and groups
                          (loop (- remaining 1) (syntax-cdr input) (cons groups iterations)))))))))

    (define (match-vector-pattern ellipsis literals pattern input)
      (and (list-syntax? input) (equal? (list-syntax-prefix input) "#")
           (null? (list-syntax-improper-tail input))
           (match-pattern-groups
            ellipsis literals (vector->list pattern)
            (make-list-syntax (list-syntax-elements input) '() (syntax-loc input) '()))))

    (define (match-bytevector-pattern pattern input)
      (and (list-syntax? input) (equal? (list-syntax-prefix input) "#u8")
           (null? (list-syntax-improper-tail input))
           (every? byte-syntax? (list-syntax-elements input))
           (equal? pattern (apply bytevector (map atom-syntax-value (list-syntax-elements input))))
           '()))

    (define (combine-match-groups left right)
      (and left right (append left right)))

    ;; Each repetition adds a list layer, preserving empty and ragged groups.
    (define (collect-repeated-match-groups names iterations)
      (if (null? names)
          '()
          (cons
           (make-match-group #f (car names)
                             (map (lambda (groups) (match-group-data (car groups))) iterations))
           (collect-repeated-match-groups (cdr names) (map cdr iterations)))))
    ))
