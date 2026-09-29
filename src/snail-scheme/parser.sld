(define-library (snail-scheme parser)
  (export parse-file test-parser)

  (import
    (scheme base)
    (scheme char)
    (snail-scheme common)
    (snail-scheme test-utils)
    (snail-scheme syntax))

  (begin
    ;
    ; Input stream
    ;

    (define-record-type <input-stream>
      (make-input-stream
        filename ; filename to include in syntax `<loc>`
        chars ; list of chars
        line ; the 1-indexed line of the first character
        column) ; the 1-indexed column of the first character
      input-stream?
      (filename input-stream-filename)
      (chars input-stream-chars)
      (line input-stream-line)
      (column input-stream-column))

    (define (string->input-stream str)
      (let
        ((chars (string->list str)))
        (list->input-stream chars)))

    (define (list->input-stream chars)
      (make-input-stream "<anonymous-input-stream>" chars 1 1))

    (define (input-stream-eof? input-stream)
      (null? (peek-input-stream input-stream)))

    (define (peek-input-stream input-stream)
      (let
        ((chars (input-stream-chars input-stream)))
        (if (null? chars) '() (car chars))))

    (define (next-input-stream input-stream)
      (let*
        ((filename (input-stream-filename input-stream))
          (old-chars (input-stream-chars input-stream))
          (old-line (input-stream-line input-stream))
          (old-column (input-stream-column input-stream))
          (car-char (car old-chars))
          (next-chars (cdr old-chars))
          ; Count CRLF as one line ending, and also accept a standalone CR.
          (newline? (or (eqv? car-char #\newline)
                     (and (eqv? car-char #\return)
                       (not (and (pair? next-chars)
                             (eqv? (car next-chars) #\newline))))))
          (next-line (if newline? (+ 1 old-line) old-line))
          (next-column (if newline? 1 (+ 1 old-column))))
        (make-input-stream filename next-chars next-line next-column)))

    (define (input-stream-loc input-stream)
      (make-loc
        (input-stream-filename input-stream)
        (input-stream-line input-stream)
        (input-stream-column input-stream)))

    ;
    ; ParseResult
    ; Do not confuse with (Parser T):
    ; Parser T := (InputStream) -> (ParseResult T)
    ;

    (define-record-type <parse-result>
      (make-parse-result
        success ; whether the parse succeeded
        value ; value payload if success, null if failure
        input) ; input-stream post-parse
      parse-result?
      (success parse-result-success)
      (value parse-result-value)
      (input parse-result-input))

    (define (parse-result-ok value input)
      (make-parse-result #t value input))

    (define (parse-result-err input)
      (make-parse-result #f '() input))

    (define (parse-result-ok? x)
      (and (parse-result? x) (parse-result-success x)))

    (define (parse-result-err? x)
      (and (parse-result? x) (not (parse-result-success x))))

    ;
    ; Basic Monadic (Parser T)
    ; Parser T := (InputStream) -> (ParseResult T)
    ; IMPORTANT: the monadic type is (Parser T), NOT (ParseResult T).
    ;

    ;;; `chain` sequences binders, starting with the value '().
    ;;;
    ;;; It is a parser combinator (i.e. its application returns a parser function) that chains
    ;;; multiple parsers together.
    ;;;   ```scheme
    ;;;   (chain
    ;;;     (lambda (value) (...))
    ;;;     (lambda (value) (...)))
    ;;;   ```
    ;;; The `chain` statement will try applying each closure in sequence until one of them fails,
    ;;; including the init.
    (define chain
      (lambda binder-list
        (let recur
          ((binder-list binder-list)
            (parser (return '())))
          (if (null? binder-list)
            parser
            (recur
              (cdr binder-list)
              (>>= parser (car binder-list)))))))

    ;;; monadic return operator for (Parser T)
    ;;;   return :: (T) -> Parser T
    (define (return value)
      (lambda (input-stream)
        (parse-result-ok value input-stream)))

    ;;; monadic return operator (fail variant) for (Parser T)
    ;;;   fail :: () -> Parser T
    (define (fail)
      (lambda (input-stream)
        (parse-result-err input-stream)))

    ;;; monadic bind operator for (Parser T)
    ;;;   >>= :: (Parser T, ((T) -> Parser U)) -> Parser U
    (define (>>= parser binder)
      (lambda (input-stream)
        (let
          ((parse-result (parser input-stream)))
          (if (parse-result-err? parse-result)
            parse-result
            (let*
              ((value (parse-result-value parse-result))
                (input (parse-result-input parse-result))
                (parser (binder value)))
              (parser input))))))

    ;
    ; Primitive parsers: written manually, not by composition
    ;

    (define (char-if predicate)
      (lambda (input-stream)
        (let
          ((peek (peek-input-stream input-stream)))
          (if (and (not (null? peek)) (predicate peek))
            (parse-result-ok peek (next-input-stream input-stream))
            (parse-result-err input-stream)))))

    (define (repeat parser)
      (lambda (input-stream)
        (let recur
          ((input-stream input-stream)
            (acc '()))
          (let
            ((parse-result (parser input-stream)))
            (if (parse-result-ok? parse-result)
              (let ((next-input (parse-result-input parse-result)))
                ; A nullable parser here is a programming error, not a parse failure.
                (if (and (= (input-stream-line input-stream) (input-stream-line next-input))
                     (= (input-stream-column input-stream) (input-stream-column next-input)))
                  (error "repeat: parser succeeded without consuming input")
                  (recur next-input (cons (parse-result-value parse-result) acc))))
              (parse-result-ok (reverse acc) input-stream))))))

    (define (choice . parsers)
      (lambda (input-stream)
        (let recur
          ((input-stream input-stream)
            (parsers parsers))
          (if (null? parsers)
            (parse-result-err input-stream)
            (let
              ((parse-result ((car parsers) input-stream)))
              (if (parse-result-ok? parse-result)
                parse-result
                (recur input-stream (cdr parsers))))))))

    (define (eof)
      (lambda (input-stream)
        (if (input-stream-eof? input-stream)
          (parse-result-ok '() input-stream)
          (parse-result-err input-stream))))

    (define (location)
      (lambda (input-stream)
        (parse-result-ok (input-stream-loc input-stream) input-stream)))

    ;
    ; Higher-order general-purpose parsers and combinators
    ;

    (define (char chr)
      (assert (char? chr))
      (char-if (lambda (c) (eqv? c chr))))

    (define (tag str)
      (tag-val str str))

    (define (tag-val str val)
      (let*
        ((char-list (string->list str))
          (char-parser-list (map char char-list))
          (tuple-parser (apply tuple char-parser-list)))
        (chain
          (lambda (_) tuple-parser)
          (lambda (t) (return val)))))

    (define (char-from lst)
      (char-if (lambda (c) (member c lst))))

    (define (repeat-at-least-once parser)
      (chain
        (lambda (_) (repeat parser))
        (lambda (v) (if (null? v) (fail) (return v)))))

    (define (discard parser)
      (chain
        (lambda (_) parser)
        (lambda (_) (return '()))))

    (define (whitespace)
      (discard (repeat (whitespace-char))))

    (define (whitespace-char)
      (discard (char-from '(#\newline #\return #\space #\tab))))

    (define (tuple . parsers)
      (let*
        ( ; `(make-binder parser)` emits a bind function suitable for `(chain binders...)`.
          ; The binder function takes in an 'accumulator' list and extends it with the parser's parsed value.
          (make-binder
            (lambda (parser)
              (lambda (reversed-accumulator-list)
                (chain
                  (lambda (_) parser)
                  (lambda (v) (return (cons v reversed-accumulator-list)))))))

          ; map `make-binder` over all the parsers to get a list of binders
          (binders (map make-binder parsers))

          ; apply `chain` on the binders to obtain a parser that returns the reversed list of binders
          (reversed-tuple-parser (apply chain binders))

          ; reverse the reversed-tuple-parser's value to obtain the final result
          (tuple-parser
            (chain
              (lambda (_) reversed-tuple-parser)
              (lambda (reversed-accumulator-list) (return (reverse reversed-accumulator-list))))))
        tuple-parser))

    (define (optional parser)
      (choice parser (return '())))

    ;
    ; Expression parsers
    ;

    (define (file)
      (chain
        (lambda (_)
          (tuple
            (repeat (expr))
            (whitespace)
            (eof)))
        (lambda (t)
          (return (first t)))))

    (define (expr)
      (chain
        (lambda (_) (whitespace))
        (lambda (_)
          (choice
            (list-expr)
            (char-expr)
            (string-expr)
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
            (whitespace)
            (right-fender)))
        (lambda (t)
          (let
            ((loc (first t))
              (elements (third t))
              (opt-tail (fourth t)))
            (if (and (null? elements) (not (null? opt-tail)))
              (fail)
              (return (make-list-syntax elements opt-tail loc)))))))

    (define (char-expr)
      (chain
        (lambda (_)
          (tuple
            (location)
            (choice
              ; Standard special characters
              (tag-val "#\\alarm" #\alarm)
              (tag-val "#\\backspace" #\backspace)
              (tag-val "#\\delete" #\delete)
              (tag-val "#\\escape" #\escape)
              (tag-val "#\\newline" #\newline)
              (tag-val "#\\null" #\null)
              (tag-val "#\\return" #\return)
              (tag-val "#\\space" #\space)
              (tag-val "#\\tab" #\tab)

              ; #\xHHHH...
              (chain
                (lambda (_) (tuple (tag "#\\x") (hexadecimal-integer)))
                (lambda (t) (unicode-character (second t))))

              ; Otherwise, consume the first character after #\
              (chain
                (lambda (_) (tuple (tag "#\\") (char-if (lambda (_) #t))))
                (lambda (t) (return (second t)))))
            (token-end)))
        (lambda (t)
          (let
            ((loc (first t))
              (chr (second t)))
            (return
              (make-atom-syntax chr loc))))))

    (define (string-expr)
      (chain
        (lambda (_)
          (tuple
            (location)
            (discard (char #\"))
            (repeat (string-expr-element))
            (discard (char #\"))))
        (lambda (t)
          (let
            ((loc (first t))
              (elements (third t)))
            (return
              (make-atom-syntax (list->string elements) loc))))))

    (define (string-expr-element)
      (choice
        (tag-val "\\a" #\alarm)
        (tag-val "\\b" #\backspace)
        (tag-val "\\t" #\tab)
        (tag-val "\\n" #\newline)
        (tag-val "\\r" #\return)
        (tag-val "\\\"" #\")
        (tag-val "\\\\" #\\)
        ; TODO: support `\` as a line delimiter

        ; #\x{HHHH...};
        ; note the trailing semicolon
        (chain
          (lambda (_) (tuple (tag "\\x") (hexadecimal-integer) (tag ";")))
          (lambda (t) (unicode-character (second t))))

        ; A backslash must introduce a supported escape.
        (char-if (lambda (c) (not (memv c '(#\" #\\)))))))

    (define (unicode-character codepoint)
      (if (and (<= 0 codepoint #x10ffff)
           (not (<= #xd800 codepoint #xdfff)))
        (return (integer->char codepoint))
        (fail)))

    ; Identifiers, numbers, characters and dot must end at a delimiter or EOF.
    (define (delimiter? c)
      (memv c '(#\space #\tab #\newline #\return #\| #\( #\) #\" #\;)))

    (define (token-end)
      (lambda (input-stream)
        (if (or (input-stream-eof? input-stream)
             (delimiter? (peek-input-stream input-stream)))
          (parse-result-ok '() input-stream)
          (parse-result-err input-stream))))

    (define (number-expr)
      ; Convert a whole token so malformed numbers cannot split into smaller atoms.
      ; Numeric forms and precision follow the host's string->number implementation.
      (chain
        (lambda (_)
          (tuple
            (location)
            (repeat-at-least-once (char-if (lambda (c) (not (delimiter? c)))))))
        (lambda (t)
          (let ((number (string->number (list->string (second t)))))
            (if number
              (return (make-atom-syntax number (first t)))
              (fail))))))

    (define (identifier-expr)
      ; TODO: parse `|`...`|` identifiers
      (chain
        (lambda (_)
          (tuple (location) (repeat-at-least-once (char-if identifier-char?)) (token-end)))
        (lambda (t)
          (let* ((chars (second t)) (name (list->string chars)))
            (if (and (identifier-start? chars) (not (string->number name)))
              (return (make-atom-syntax (string->symbol name) (first t)))
              (fail))))))

    (define (identifier-initial? c)
      (or (char-alphabetic? c) (memv c '(#\! #\$ #\% #\& #\* #\/ #\: #\< #\= #\> #\? #\^ #\_ #\~))))

    (define (identifier-char? c)
      (or (identifier-initial? c) (char<=? #\0 c #\9) (memv c '(#\+ #\- #\. #\@))))

    (define (sign-subsequent? c)
      (or (identifier-initial? c) (memv c '(#\+ #\- #\@))))

    (define (dot-subsequent? c)
      (or (sign-subsequent? c) (eqv? c #\.)))

    (define (identifier-start? chars)
      (let ((head (car chars)) (tail (cdr chars)))
        (cond
          ((identifier-initial? head) #t)
          ((memv head '(#\+ #\-))
            (or (null? tail)
              (sign-subsequent? (car tail))
              (and (eqv? (car tail) #\.)
                (pair? (cdr tail))
                (dot-subsequent? (cadr tail)))))
          ((eqv? head #\.)
            (and (pair? tail) (dot-subsequent? (car tail))))
          (else #f))))

    (define (quote-expr)
      (chain
        (lambda (_)
          (tuple
            (location)
            (choice (tag-val "'" 'quote)
              (tag-val "`" 'quasiquote)
              (tag-val ",@" 'unquote-splicing)
              (tag-val "," 'unquote))
            (expr)))
        (lambda (t)
          (let ((loc (first t)))
            (return (make-list-syntax
                     (list (make-atom-syntax (second t) loc) (third t))
                     '()
                     loc))))))

    (define (left-fender)
      (discard (char #\()))

    (define (right-fender)
      (discard (char #\))))

    (define (improper-tail)
      (optional
        (chain
          (lambda (_) (tuple (whitespace) (char #\.) (token-end)))
          (lambda (_) (expr)))))

    (define (hexadecimal-integer)
      (chain
        (lambda (_) (repeat-at-least-once (hexadecimal-digit)))
        (lambda (digits) (return (string->number (list->string digits) 16)))))

    (define (hexadecimal-digit)
      (char-if
        (lambda (c) (member c (string->list "0123456789abcdefABCDEF")))))

    (define (decimal-integer)
      (chain
        (lambda (_) (repeat-at-least-once (decimal-digit)))
        (lambda (digits) (return (string->number (list->string digits) 10)))))

    (define (decimal-digit)
      (char-if
        (lambda (c) (member c (string->list "0123456789")))))

    ;
    ; Public API
    ;

    (define (parse-file filename content)
      (let*
        ((input-stream (make-input-stream filename (string->list content) 1 1))
          (parse-result ((file) input-stream)))
        (if (parse-result-ok? parse-result)
          (parse-result-value parse-result)
          (error "parse failed" filename parse-result)))))

  (include "parser-tests.scm"))
