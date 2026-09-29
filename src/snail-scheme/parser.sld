(define-library (snail-scheme parser)
  (export
    parse-file

    test-input-stream
    test->>=
    test-char-if
    test-repeat
    test-chain
    test-discard
    test-tuple
    test-optional
    test-tag)

  (import
    (scheme base)
    (scheme read)
    (scheme write)
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
        line ; the 1-indexed line of the first cluster in the list
        column) ; the 1-indexed column of the first cluster in the list
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
          (next-line (next-input-stream-line car-char old-line))
          (next-column (next-input-stream-column car-char old-column)))
        (make-input-stream filename next-chars next-line next-column)))

    (define (next-input-stream-line advanced-char line)
      (if (eqv? advanced-char #\newline) (+ 1 line) line))

    (define (next-input-stream-column advanced-char column)
      (if (eqv? advanced-char #\newline) 1 (+ 1 column)))

    (define (input-stream-loc input-stream)
      (make-loc
        (input-stream-filename input-stream)
        (input-stream-line input-stream)
        (input-stream-column input-stream)))

    (define (test-input-stream)
      (let*
        ((is (list->input-stream '(#\a #\newline #\b)))
          (fn (input-stream-filename is))
          (_ (expect is (make-input-stream fn '(#\a #\newline #\b) 1 1)))
          (_ (expect (peek-input-stream is) #\a))
          (is (next-input-stream is))
          (_ (expect is (make-input-stream fn '(#\newline #\b) 1 2)))
          (_ (expect (peek-input-stream is) #\newline))
          (is (next-input-stream is))
          (_ (expect is (make-input-stream fn '(#\b) 2 1)))
          (_ (expect (peek-input-stream is) #\b))
          (is (next-input-stream is))
          (_ (expect is (make-input-stream fn '() 2 2)))
          (_ (expect (peek-input-stream is) '())))
        '()))

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

    ;;; `chain` produces behavior like a Haskell `chain` block.
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
              (recur
                (parse-result-input parse-result)
                (cons (parse-result-value parse-result) acc))
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
        (lambda (_) parser)
        (lambda (v) (if (null? v) (fail) (return v)))))

    (define (discard parser)
      (chain
        (lambda (_) parser)
        (lambda (_) (return '()))))

    (define (whitespace)
      (discard (repeat (whitespace-char))))

    (define (whitespace-char)
      (discard (char-from '(#\newline #\space #\tab))))

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
    ; Parser combinator tests
    ;

    (define (test->>=)
      (let*
        ((input-stream (string->input-stream "a"))

          (a (char #\a))
          (parse-result (a input-stream))
          (_ (assert (parse-result-ok? parse-result)))
          (_ (expect #\a (parse-result-value parse-result)))

          (y (>>= a (lambda (v) (return (string v)))))
          (parse-result (y input-stream))
          (_ (assert (parse-result-ok? parse-result)))
          (_ (expect "a" (parse-result-value parse-result))))
        '()))

    (define (test-chain)
      (let*
        ((input-stream (string->input-stream "abc"))

          (abc
            (chain
              (lambda (_) (char #\a))
              (lambda (_) (char #\b))
              (lambda (_) (char #\c))))

          (parse-result (abc input-stream))
          (_ (assert (parse-result-ok? parse-result))))
        '()))

    (define (test-char-if)
      (let*
        ( ; init input stream to "ab"
          (input-stream (string->input-stream "ab"))

          ; parse "a"
          (pc (char-if (lambda (v) (eqv? v #\a))))
          (pr (pc input-stream))
          (_ (assert (parse-result-success pr)))
          (_ (expect #\a (parse-result-value pr)))

          ; try parsing "a" again, will fail
          (input-stream (parse-result-input pr))
          (pr (pc input-stream))
          (_ (assert (not (parse-result-success pr))))
          (_ (expect '() (parse-result-value pr)))

          ; try parsing "b" now, with the input stream from the failed result.
          (input-stream (parse-result-input pr))
          (pc (char-if (lambda (v) (eqv? v #\b))))
          (pr (pc input-stream))
          (_ (assert (parse-result-success pr)))
          (_ (expect #\b (parse-result-value pr)))

          ; expect input stream input-stream at EOF
          (input-stream (parse-result-input pr))
          (_ (expect (peek-input-stream input-stream) '())))
        '()))

    (define (test-repeat)
      (let*
        ( ; init input stream to "aaab"
          ; define pc as a single character parser
          (input-stream (string->input-stream "aaab"))

          ; parse "a" repeatedly with repeat
          (a (repeat (char #\a)))
          (parse-result (a input-stream))
          (_ (assert (parse-result-ok? parse-result)))
          (_ (expect '(#\a #\a #\a) (parse-result-value parse-result)))

          ; parse "a" again should succeed with length 0
          (input-stream (parse-result-input parse-result))
          (parse-result (a input-stream))
          (_ (assert (parse-result-ok? parse-result)))
          (_ (expect '() (parse-result-value parse-result)))

          ; parse "a" again with repeat-at-least-once should fail
          (parse-result ((repeat-at-least-once (char #\a)) input-stream))
          (_ (assert (parse-result-err? parse-result)))

          ; parse "b" with repeat should succeed with length 1
          (input-stream (parse-result-input parse-result))
          (parse-result ((repeat (char #\b)) input-stream))
          (_ (assert (parse-result-ok? parse-result)))
          (_ (expect '(#\b) (parse-result-value parse-result))))
        '()))

    (define (test-discard)
      (let*
        ((input-stream (string->input-stream "a"))

          ; the parser `a := (char #\a)` should return value `#\a`
          (a (char #\a))
          (parse-result (a input-stream))
          (_ (assert (parse-result-ok? parse-result)))
          (_ (expect #\a (parse-result-value parse-result)))
          (_ (assert (input-stream-eof? (parse-result-input parse-result))))

          ; the parser `d := (discard a)` should return value `'()`
          ; even though the post-input-stream should be empty
          (d (discard a))
          (parse-result (d input-stream))
          (_ (assert (parse-result-ok? parse-result)))
          (_ (assert (null? (parse-result-value parse-result))))
          (_ (assert (input-stream-eof? (parse-result-input parse-result)))))
        '()))

    (define (test-tuple)
      (let*
        ((input-stream (string->input-stream "abcd"))

          (abcd (tuple (char #\a) (char #\b) (char #\c) (char #\d)))
          (parse-result (abcd input-stream))
          (_ (assert (parse-result-ok? parse-result)))
          (_ (expect '(#\a #\b #\c #\d) (parse-result-value parse-result)))
          (_ (assert (input-stream-eof? (parse-result-input parse-result)))))
        '()))

    (define (test-optional)
      (let*
        ((input-stream (string->input-stream "a"))

          (aa (tuple (char #\a) (optional (char #\a))))
          (parse-result (aa input-stream))
          (_ (assert (parse-result-ok? parse-result)))
          (_ (expect '(#\a ()) (parse-result-value parse-result)))
          (_ (assert (input-stream-eof? (parse-result-input parse-result)))))
        '()))

    (define (test-tag)
      (let*
        ((input-stream (string->input-stream "abc"))

          (abc (tag "abc"))
          (parse-result (abc input-stream))
          (_ (assert (parse-result-ok? parse-result)))
          (_ (expect "abc" (parse-result-value parse-result)))
          (_ (assert (input-stream-eof? (parse-result-input parse-result)))))
        '()))

    ;
    ; Expression parsers
    ;

    (define (file)
      (chain
        (lambda (_)
          (tuple
            (repeat (expr))
            (eof)))
        (lambda (t)
          (return (first t)))))

    (define (expr)
      (chain
        (lambda (_) (discard (whitespace)))
        (lambda (_)
          (choice
            (list-expr)
            (char-expr)
            (string-expr)
            (number-expr)
            (identifier-expr)

            ; TODO: support quote, quasiquote
            ; quote-expr

            ))))

    (define (list-expr)
      (chain
        (lambda (_)
          (tuple
            (location)
            (left-fender)
            (repeat-at-least-once (expr))
            (improper-tail)
            (right-fender)))
        (lambda (t)
          (let
            ((loc (first t))
              (elements (third t))
              (opt-tail (fourth t)))
            (return (make-list-syntax elements opt-tail loc))))))

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
                (lambda (t) (return (second t))))

              ; Otherwise, consume the first character after #\
              (chain
                (lambda (_) (tuple (tag "#\\") (char-if (lambda (_) #t))))
                (lambda (t) (return (second t)))))))
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
            (optional (whitespace))
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
          (lambda (t) (return (integer->char (second t)))))

        ; else, any character that isn't `"`
        (char-if (lambda (c) (not (eqv? c #\"))))))

    (define (number-expr)
      ; TODO: flesh out numbers, required to parse identifier correctly too
      (choice
        (decimal-integer)
        (chain
          (lambda (_) (tuple (tag "#x") (hexadecimal-integer)))
          (lambda (t) (return (second t))))))

    (define (identifier-expr)
      ; TODO: parse `|`...`|` identifiers
      (repeat-at-least-once (char-if identifier-char?)))

    (define (identifier-char? c)
      (not (member c '(#\space #\. #\( #\) #\;))))

    (define (left-fender)
      (discard (char #\()))

    (define (right-fender)
      (discard (char #\))))

    (define (improper-tail)
      (optional
        (chain
          (lambda (_) (tuple (whitespace) (char #\.)))
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
    ; Language parser tests
    ;

    ; TODO

    ;
    ; Public API
    ;

    (define (parse-file filename content)
      (let*
        ((input-stream (make-input-stream filename (string->list content) 1 1))
          (parse-result ((file) input-stream)))
        (if (parse-result-ok? parse-result)
          (parse-result-value parse-result)
          (error "parse failed" filename parse-result))))))
