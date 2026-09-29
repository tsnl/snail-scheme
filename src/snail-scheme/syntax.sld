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
   line-comment
   block-comment
   datum-comment
   token
   token-end)

  (import
   (scheme base)
   (scheme char)
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
      ;; Intertoken space includes line, nested block and datum comments.
      (discard (repeat (choice (whitespace-char) (line-comment) (block-comment) (datum-comment)))))

    (define (whitespace-char)
      (discard (char-from '(#\newline #\return #\space #\tab))))

    (define (line-comment)
      (discard
       (tuple (char #\;)
              (repeat (char-if (lambda (c) (not (memv c '(#\newline #\return)))))))))

    (define (block-comment)
      (chain
       (lambda (_) (tag "#|"))
       (lambda (_)
         (lambda (input)
           (let loop ((input input) (depth 1))
             (let ((open ((tag "#|") input))
                   (close ((tag "|#") input)))
               (cond
                ((parse-result-ok? open)
                 (loop (parse-result-input open) (+ depth 1)))
                ((parse-result-ok? close)
                 (if (= depth 1)
                     (parse-result-ok '() (parse-result-input close))
                     (loop (parse-result-input close) (- depth 1))))
                ((reader-eof? input) (parse-result-err input))
                (else (loop (next-reader input) depth)))))))))

    (define (datum-comment)
      (discard
       (chain
        (lambda (_) (tag "#;"))
        (lambda (_) (expr)))))

    ;;
    ;; Expression parsers
    ;;

    (define (file)
      (pmap (tuple (repeat (expr)) (whitespace) (eof)) first))

    (define (expr)
      (chain
       (lambda (_) (whitespace))
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
          (whitespace)
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
         (pmap (tuple (tag "#\\") (char-if (lambda (_) #t))) second))
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
       (char-if (lambda (c) (not (memv c '(#\" #\\)))))))

    (define (unicode-character codepoint)
      (if (and (<= 0 codepoint #x10ffff)
               (not (<= #xd800 codepoint #xdfff)))
          (return (integer->char codepoint))
          (fail)))

    ;; Identifiers, numbers, characters and dot must end at a delimiter or EOF.
    (define (delimiter? c)
      (memv c '(#\space #\tab #\newline #\return #\| #\( #\) #\" #\;)))

    (define (token-end)
      (lambda (reader)
        (if (or (reader-eof? reader)
                (delimiter? (peek-reader reader)))
            (parse-result-ok '() reader)
            (parse-result-err reader))))

    (define (token)
      (pmap (repeat-at-least-once (char-if (lambda (c) (not (delimiter? c))))) list->string))

    (define (boolean-expr)
      (chain
       (lambda (_) (tuple (location) (token)))
       (lambda (t)
         (let ((text (string-downcase (second t))) (loc (first t)))
           (cond
            ((member text '("#t" "#true")) (return (make-atom-syntax #t loc)))
            ((member text '("#f" "#false")) (return (make-atom-syntax #f loc)))
            (else (fail)))))))

    (define (number-expr)
      ;; Convert a whole token so malformed numbers cannot split into smaller atoms.
      ;; Numeric forms and precision follow the host's string->number implementation.
      (chain
       (lambda (_) (tuple (location) (token)))
       (lambda (t)
         (let ((number (string->number (second t))))
           (if number
               (return (make-atom-syntax number (first t)))
               (fail))))))

    (define (identifier-expr)
      ;; TODO: parse `|`...`|` identifiers
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
        (lambda (_) (tuple (whitespace) (char #\.) (token-end)))
        (lambda (_) (expr)))))

    (define (hexadecimal-integer)
      (pmap (repeat-at-least-once (hexadecimal-digit))
            (lambda (digits) (string->number (list->string digits) 16))))

    (define (hexadecimal-digit)
      (char-if
       (lambda (c) (member c (string->list "0123456789abcdefABCDEF")))))

    (define (decimal-integer)
      (pmap (repeat-at-least-once (decimal-digit))
            (lambda (digits) (string->number (list->string digits) 10))))

    (define (decimal-digit)
      (char-if
       (lambda (c) (member c (string->list "0123456789")))))

    ;;
    ;; Public API
    ;;

    (define (parse-file reader)
      (let ((parse-result ((file) reader)))
        (if (parse-result-ok? parse-result)
            (parse-result-value parse-result)
            (error "parse failed" (reader-filename reader) parse-result))))))
