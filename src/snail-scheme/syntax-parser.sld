;; Named parsers are immutable values, constructed once during library loading.
;; Compose them directly (choice s-number s-symbol); apply one to a reader with
;; (s-atom reader). Readers, values, source locations, and failures are per-parse.
;;
;; This module deliberately uses dependency order, unlike our usual
;; high-level-before-dependencies convention, so each parser's prerequisites
;; are initialized first. Recursive references stay inside parsing callbacks:
;; s-expr defers its alternatives, block-comment its body, and datum-comment its
;; expression. Those callbacks run only after the library is initialized.
(define-library (snail-scheme syntax-parser)
  (export reader->syntax-list s-file s-expr s-atom number-literal? char-literal? symbol-literal?)

  (import
   (snail-scheme trace)
   (scheme base)
   (snail-scheme common)
   (snail-scheme reader)
   (snail-scheme parser)
   (snail-scheme syntax))

  (begin

    ;; ---- Literal predicates ----

    ;; These string APIs reuse the grammar; syntax rules never call them.
    (define (number-literal? text)
      (assert (string? text))
      (parse-result-ok?
       ((tuple
         numeric-spelling
         (eof))
        (string->reader "<number-literal>" text))))

    (define (char-literal? text)
      (assert (string? text))
      (parse-result-ok?
       ((tuple
         character-literal
         (eof))
        (string->reader "<char-literal>" text))))

    (define (symbol-literal? text)
      (assert (string? text))
      (parse-result-ok?
       ((tuple
         identifier
         (eof))
        (string->reader "<symbol-literal>" text))))

    ;; ---- Numeric spellings ----

    ;; Join the character/string results nested by tuple and repeat.
    (define (spelling->string spelling)
      (cond
       ((char? spelling) (string spelling))
       ((string? spelling) spelling)
       (else (apply string-append (map spelling->string spelling)))))

    (define hexadecimal-digit
      (char-if char-hexadecimal-digit?))

    (define decimal-digit
      (char-if char-decimal-digit?))

    (define hexadecimal-integer
      (pmap (repeat-at-least-once hexadecimal-digit)
            (lambda (digits) (string->number (list->string digits) 16))))

    (define decimal-integer
      (pmap (repeat-at-least-once decimal-digit)
            (lambda (digits) (string->number (list->string digits) 10))))

    (define exactness
      (choice
       (tag-ci "#e")
       (tag-ci "#i")))

    (define exponent
      (tuple
       (tag-ci "e")
       (optional (char-if char-sign?))
       (repeat-at-least-once decimal-digit)))

    ;; decimal <- (digit+ "." digit* / "." digit+ / digit+) exponent?
    (define decimal-number
      (tuple
       (choice
        (tuple
         (repeat-at-least-once decimal-digit)
         (char #\.)
         (repeat decimal-digit))
        (tuple
         (char #\.)
         (repeat-at-least-once decimal-digit))
        (repeat-at-least-once decimal-digit))
       (optional exponent)))

    (define unsigned-special-real
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
           decimal-number
           (repeat-at-least-once (char-if digit?)))))

    (define (real-number digit? decimal?)
      (choice
       (tuple
        (char-if char-sign?)
        unsigned-special-real)
       (tuple
        (optional (char-if char-sign?))
        (unsigned-real digit? decimal?))))

    (define (imaginary-number digit? decimal?)
      (tuple
       (char-if char-sign?)
       (optional
        (choice
         unsigned-special-real
         (unsigned-real digit? decimal?)))
       (tag-ci "i")))

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

    ;; prefix <- radix exactness? / exactness radix?
    ;; Only decimal may omit the radix marker.
    (define (number-prefix radix)
      (choice
       (tuple
        (tag-ci radix)
        (optional exactness))
       (tuple
        exactness
        (if (equal? radix "#d") (optional (tag-ci radix)) (tag-ci radix)))))

    (define (radix-number radix digit? decimal?)
      (tuple
       (if decimal? (optional (number-prefix radix)) (number-prefix radix))
       (complex-number digit? decimal?)))

    (define numeric-spelling-body
      (pmap
       (choice
        (radix-number "#b" char-binary-digit? #f)
        (radix-number "#o" char-octal-digit? #f)
        (radix-number "#x" char-hexadecimal-digit? #f)
        (radix-number "#d" char-decimal-digit? #t))
       spelling->string))

    ;; Every number starts with a prefix marker, sign, dot, or decimal digit.
    ;; Skip the nested alternatives for other starts; they would all retry the
    ;; same character, both here and in the identifier's numeric exclusion.
    (define numeric-spelling
      (chain
       (lookahead
        (char-if (lambda (character)
                   (or (char-decimal-digit? character)
                       (memv character '(#\# #\+ #\- #\.))))))
       (lambda (_) numeric-spelling-body)))

    ;; ---- Identifier spellings ----

    ;; R7RS identifiers beginning with +, -, or . need distinct initial rules.
    (define peculiar-identifier
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

    (define identifier
      (pmap
       (tuple
        ;; Numeric spellings such as +i and +inf.0 take precedence over identifiers.
        (not-followed-by
         (tuple
          numeric-spelling
          (not-followed-by (char-if char-bare-atom?))))
        (optional (tag "#%-"))
        (choice
         (tuple
          (char-if char-identifier-initial?)
          (repeat (char-if char-identifier-subsequent?)))
         peculiar-identifier))
       spelling->string))

    ;; ---- Delimited text and characters ----

    (define (unicode-character codepoint)
      (if (and (<= 0 codepoint #x10ffff) (not (<= #xd800 codepoint #xdfff)))
          (return (integer->char codepoint))
          (fail)))

    (define escaped-character
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
         `(codepoint . ,hexadecimal-integer)
         `(_ . ,(char #\;)))
        (lambda (fields) (unicode-character (cdr (assq 'codepoint fields)))))))

    (define character-literal
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
         `(codepoint . ,hexadecimal-integer))
        (lambda (fields) (unicode-character (cdr (assq 'codepoint fields)))))
       ;; The character after #\ may itself be a delimiter.
       (chain (tag "#\\") (lambda (_) (char-if char?)))))

    (define string-literal
      (pmap
       (named-tuple
        `(_ . ,(char #\"))
        `(characters . ,(repeat
                         (choice
                          escaped-character
                          (char-if char-string-literal?))))
        `(_ . ,(char #\")))
       (lambda (fields) (list->string (cdr (assq 'characters fields))))))

    ;; ---- Whitespace and comments ----

    (define whitespace-char
      (discard (char-if char-intertoken-space?)))

    (define whitespace
      (discard (repeat whitespace-char)))

    (define line-comment
      (discard
       (tuple
        (char #\;)
        (repeat (char-if char-line-comment?)))))

    ;; block-comment <- "#|" (block-comment / !("#|" / "|#") .)* "|#"
    (define block-comment
      (discard
       (chain
        (tag "#|")
        (lambda (_)
          (tuple
           (repeat block-comment-element)
           (tag "|#"))))))

    (define block-comment-element
      (choice
       block-comment
       (tuple
        (not-followed-by
         (choice
          (tag "#|")
          (tag "|#")))
        (char-if char?))))

    (define datum-comment
      (discard (chain (tag "#;") (lambda (_) s-expr))))

    (define intertoken-space
      (discard
       (repeat-at-least-once
        (choice
         ;; Require progress before repeating the nullable whitespace rule.
         (tuple
          whitespace-char
          whitespace)
         line-comment
         block-comment
         datum-comment))))

    ;; ---- Delimited sequences ----

    (define (fenced-elements open close element)
      (pmap
       (named-tuple
        `(_ . ,(char open))
        `(elements . ,(repeat element))
        `(_ . ,(optional intertoken-space))
        `(_ . ,(char close)))
       (lambda (fields) (cdr (assq 'elements fields)))))

    ;; ---- Atomic literals ----

    (define s-pipe-symbol
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(_ . ,(char #\|))
        `(characters . ,(repeat
                         (choice
                          escaped-character
                          (char-if char-quoted-identifier?))))
        `(_ . ,(char #\|)))
       (lambda (fields)
         (make-atom-syntax (string->symbol (list->string (cdr (assq 'characters fields))))
                           (cdr (assq 'loc fields))))))

    (define s-string
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(value . ,string-literal))
       (lambda (fields)
         (make-atom-syntax (cdr (assq 'value fields)) (cdr (assq 'loc fields))))))

    (define s-char
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(value . ,character-literal)
        `(_ . ,(not-followed-by (char-if char-bare-atom?))))
       (lambda (fields)
         (make-atom-syntax (cdr (assq 'value fields)) (cdr (assq 'loc fields))))))

    (define s-boolean
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

    (define s-number
      (chain
       (named-tuple
        `(loc . ,(location))
        `(text . ,numeric-spelling)
        `(_ . ,(not-followed-by (char-if char-bare-atom?))))
       (lambda (fields)
         (let ((number (string->number (cdr (assq 'text fields)))))
           (if number
               (return (make-atom-syntax number (cdr (assq 'loc fields))))
               (fail))))))

    (define s-symbol
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(text . ,identifier)
        `(_ . ,(not-followed-by (char-if char-bare-atom?))))
       (lambda (fields)
         (make-atom-syntax (string->symbol (cdr (assq 'text fields)))
                           (cdr (assq 'loc fields))))))

    (define byte-element
      (where
       (pmap
        (named-tuple
         `(_ . ,(optional intertoken-space))
         `(number . ,s-number))
        (lambda (fields) (atom-syntax-value (cdr (assq 'number fields)))))
       (lambda (value) (and (exact-integer? value) (<= 0 value 255)))))

    (define s-bytevector
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(_ . ,(tag-ci "#u8"))
        `(bytes . ,(choice
                    (fenced-elements #\( #\) byte-element)
                    (fenced-elements #\[ #\] byte-element)
                    (fenced-elements #\{ #\} byte-element))))
       (lambda (fields)
         (make-atom-syntax (apply bytevector (cdr (assq 'bytes fields)))
                           (cdr (assq 'loc fields))))))

    (define s-atom
      (choice
       s-pipe-symbol
       s-string
       s-bytevector
       s-char
       s-boolean
       s-number
       s-symbol))

    ;; ---- Expressions, lists, vectors, and quote abbreviations ----

    (define s-expr
      (chain
       (optional intertoken-space)
       (lambda (_)
         (choice
          s-list
          s-vector
          s-quote
          s-atom))))

    (define improper-tail
      (chain
       (tuple
        (optional intertoken-space)
        (char #\.)
        (not-followed-by (char-if char-bare-atom?)))
       (lambda (_) s-expr)))

    (define (fenced-improper-list open close)
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(_ . ,(char open))
        `(elements . ,(repeat-at-least-once s-expr))
        `(tail . ,improper-tail)
        `(_ . ,(optional intertoken-space))
        `(_ . ,(char close)))
       (lambda (fields)
         (make-list-syntax (cdr (assq 'elements fields)) (cdr (assq 'tail fields))
                           (cdr (assq 'loc fields))))))

    (define improper-list
      (choice
       (fenced-improper-list #\( #\))
       (fenced-improper-list #\[ #\])
       (fenced-improper-list #\{ #\})))

    (define s-list
      (choice
       (pmap
        (named-tuple
         `(loc . ,(location))
         `(elements . ,(choice
                        (fenced-elements #\( #\) s-expr)
                        (fenced-elements #\[ #\] s-expr)
                        (fenced-elements #\{ #\} s-expr))))
        (lambda (fields)
          (make-list-syntax (cdr (assq 'elements fields)) '() (cdr (assq 'loc fields)))))
       improper-list))

    (define s-vector
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(_ . ,(tag "#"))
        `(elements . ,(choice
                       (fenced-elements #\( #\) s-expr)
                       (fenced-elements #\[ #\] s-expr)
                       (fenced-elements #\{ #\} s-expr))))
       (lambda (fields)
         (make-vector-syntax (cdr (assq 'elements fields)) (cdr (assq 'loc fields))))))

    (define s-quote
      (pmap
       (named-tuple
        `(loc . ,(location))
        `(name . ,(choice
                   (tag-val "'" 'quote)
                   (tag-val "`" 'quasiquote)
                   (tag-val ",@" 'unquote-splicing)
                   (tag-val "," 'unquote)))
        `(value . ,s-expr))
       (lambda (fields)
         (let ((loc (cdr (assq 'loc fields))))
           (make-list-syntax
            (list (make-atom-syntax (cdr (assq 'name fields)) loc)
                  (cdr (assq 'value fields)))
            '() loc)))))

    ;; ---- Complete files ----

    (define s-file
      (pmap
       (named-tuple
        `(forms . ,(repeat s-expr))
        `(_ . ,(optional intertoken-space))
        `(_ . ,(eof)))
       (lambda (fields) (cdr (assq 'forms fields)))))

    ;; A complete source reader becomes located syntax, or raises a located error.
    (define-traced (reader->syntax-list reader)
      (let ((result (s-file reader)))
        (if (parse-result-err? result)
            (error "cannot parse Scheme source" (reader-filename reader)
                   (reader-loc (parse-result-input result))))
        (parse-result-value result)))
    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-syntax-parser)
    (import (snail-scheme test-utils) (snail-scheme source))
    (begin
      ;; Compare location fields explicitly instead of relying on record equality.
      (define (test-value value)
        (cond
         ((loc? value) (list (loc-filename value) (loc-line value) (loc-column value)))
         ((pair? value) (cons (test-value (car value)) (test-value (cdr value))))
         (else value)))

      (define (at line column)
        (make-loc "<anonymous-reader>" line column))

      ;; Success defaults to consuming all input; failure defaults to consuming none.
      ;; Supply a remainder to check prefix parsers and failures after partial progress.
      (define (check-parser-ok parser text value . remainder)
        (let ((result (parser (string->reader "<anonymous-reader>" text))))
          (expect
           (list text (parse-result-ok? result) (test-value (parse-result-value result))
                 (list->string (reader-chars (parse-result-input result))))
           (list text #t (test-value value) (if (null? remainder) "" (car remainder))))))

      (define (check-fail parser text . remainder)
        (let ((result (parser (string->reader "<anonymous-reader>" text))))
          (expect
           (list text (parse-result-err? result) (parse-result-value result)
                 (list->string (reader-chars (parse-result-input result))))
           (list text #t '() (if (null? remainder) text (car remainder))))))

      ;; Compare syntax structurally, including source locations at every node.
      (define (syntax-value value)
        (cond
         ((atom-syntax? value)
          (list 'atom (atom-syntax-value value) (syntax-value (syntax-loc value))))
         ((list-syntax? value)
          (list 'list
                (syntax-value (list-syntax-elements value))
                (syntax-value (list-syntax-improper-tail value))
                (syntax-value (syntax-loc value))))
         ((vector-syntax? value)
          (list 'vector
                (syntax-value (vector-syntax-elements value))
                (syntax-value (syntax-loc value))))
         ((loc? value)
          (list (loc-filename value) (loc-line value) (loc-column value)))
         ((pair? value) (cons (syntax-value (car value)) (syntax-value (cdr value))))
         (else value)))

      (define (atom value line column)
        (make-atom-syntax value (at line column)))

      (define (check-ok parser text value . remainder)
        (apply check-parser-ok (pmap parser syntax-value) text (syntax-value value) remainder))

      (define (test-shared-rule-inputs)
        (let ((parser s-expr))
          (check-fail parser "(")
          (for-each
           (lambda (filename)
             (let* ((result (parser (string->reader filename "\n'x")))
                    (form (parse-result-value result)))
               (expect (parse-result-ok? result) #t)
               (expect (syntax->datum form) '(quote x))
               (expect (test-value (syntax-loc form)) (list filename 2 1))))
           '("first.scm" "second.scm"))
          (check-ok parser "next" (atom 'next 1 1))))

      (define (test-whitespace)
        (check-ok whitespace "" '())
        (check-ok whitespace " \t\n\ra" '() "a")
        (check-ok whitespace "a" '() "a")
        (check-ok whitespace " ; comment" '() "; comment")
        (check-ok whitespace "#| comment |#" '() "#| comment |#")
        (check-fail whitespace-char "a"))

      (define (test-intertoken-space)
        (let ((forms (pmap s-file (lambda (forms) (map syntax->datum forms)))))
          (check-ok forms "" '())
          (check-ok forms "x" '(x))
          (check-ok forms " \t\n\rx" '(x))
          (check-ok forms " ; line\n#| block |# #; ignored \tx" '(x))
          (check-ok forms "x ; trailing\n#| block |# #; ignored" '(x))))

      (define (test-comments)
        (check-ok line-comment "; comment\nx" '() "\nx")
        (check-ok line-comment "; comment" '())
        (check-fail line-comment "x")
        (check-ok block-comment "#| outer #| inner |# end |#x" '() "x")
        (check-ok block-comment "#||#" '())
        (check-fail block-comment "#| unfinished" "")
        (check-ok datum-comment "#;(a . b)x" '() "x")
        (check-ok datum-comment "#;#;a b c" '() " c")
        (check-fail datum-comment "#;" "")
        (check-ok s-file "; line\n#| block |# #; ignored " '())
        (check-ok s-file "; line\n#;#t x" (list (atom 'x 2 6)))
        (check-ok s-list "(;line\n a #;b . #|tail|# c )"
                  (make-list-syntax (list (atom 'a 2 2)) (atom 'c 2 19) (at 1 1)))
        (check-fail s-file "#| unfinished")
        (check-fail s-file "#;")
        (check-fail s-file "#| outer #| unfinished |#")
        (check-ok block-comment "#| # #| nested |# | |#x" '() "x"))

      (define (test-s-boolean)
        (check-ok s-boolean "#t" (atom #t 1 1))
        (check-ok s-boolean "#FALSE" (atom #f 1 1))
        (check-ok s-boolean "#True)" (atom #t 1 1) ")")
        (check-fail s-boolean "#trueish" "ish")
        (check-fail s-boolean "#t1" "1")
        (check-fail s-boolean ""))

      (define (test-integers)
        (check-ok decimal-digit "9a" #\9 "a")
        (check-fail decimal-digit "a")
        (check-ok hexadecimal-digit "Fz" #\F "z")
        (check-fail hexadecimal-digit "g")
        (check-ok decimal-integer "123a" 123 "a")
        (check-ok hexadecimal-integer "aFz" 175 "z")
        (check-fail decimal-integer "")
        (check-fail hexadecimal-integer "g"))

      (define (test-s-number)
        ;; Even inactive tests must be readable by the bootstrap. Decode the
        ;; rational and complex expectations only when running on the host.
        (for-each
         (lambda (case)
           (let ((value (cadr case)))
             (check-ok s-number (car case)
                       (atom (if (string? value) (string->number value) value) 1 1))))
         '(("0" 0) ("123" 123) ("-12" -12) ("#xFF" 255)
           ("#b101" 5)
           ("#o17" 15)
           ("#d12" 12)
           ("3/4" "3/4")
           ("1.25" 1.25)
           ("2e3" 2000.0)
           ("#e1.25" "5/4")
           ("1+2i" "1+2i")
           ("#E#Xf/f" 1) ("#x#e10" 16) ("#e#d1.25" "5/4")
           ("#i#b10" 2.0) ("#D#I12" 12.0) ("#O17" 15)
           (".5" 0.5) ("1." 1.0) ("-1.25E-2" -0.0125)
           ("+i" "+i") ("-i" "-i") ("+2i" "+2i") ("2-i" "2-i")
           ("1/2+3/4i" "1/2+3/4i") ("1e2-5e-1i" "100.0-0.5i")
           ("+inf.0" +inf.0) ("-inf.0" -inf.0) ("2@0" 2)))
        (check-ok s-number "12)" (atom 12 1 1) ")")
        (check-fail s-number "12abc" "abc")
        (check-fail s-number "#x")
        (check-fail s-number "#e1/0" "")
        (check-fail s-number ""))

      (define (test-number-failure-position)
        (for-each
         (lambda (text)
           (let* ((reader (make-reader "number.scm" (string->list text) 3 7))
                  (result (s-number reader)))
             (expect (parse-result-err? result) #t)
             (expect (eq? (parse-result-input result) reader) #t)))
         '("" "hello" "f" "i" "inf.0" "nan.0" "λ" "١" " " "\n" "(")))

      (define (test-symbols)
        (for-each
         (lambda (name) (check-ok s-symbol name (atom (string->symbol name) 1 1)))
         '("hello?" "a.b" "+" "-" "..." "+.x" ".x" "+item" "+inf.0x" "-inf.0x" "+@x" "-.." "λ"
           "#%-λ" "#%-Π" "#%-syntax-rules" "#%-def" "→"))
        (check-ok s-symbol "abc\t" (atom 'abc 1 1) "\t")
        (check-ok s-symbol "abc\n" (atom 'abc 1 1) "\n")
        (check-fail s-symbol "12abc")
        (check-fail s-symbol "abc#t" "#t")
        (check-fail s-symbol "#%-" "")
        (check-fail s-symbol "#%-def#t" "#t")
        (check-fail s-symbol ".")
        (check-fail s-symbol "\"unterminated"))

      (define (test-number-symbol-boundaries)
        (for-each
         (lambda (text)
           (check-fail s-symbol text)
           (expect (number? (atom-syntax-value
                             (parse-result-value (s-atom (string->reader "number.scm" text)))))
                   #t))
         '("+12" ".12" "+i" "+inf.0" "+nan.0"))
        (for-each
         (lambda (text)
           (check-ok s-atom text (atom (string->symbol text) 1 1))
           (expect (parse-result-err? (s-number (string->reader "symbol.scm" text))) #t))
         '("hello" "f" "i" "inf.0" "nan.0" "λ" "+name" ".name" "+item" "+inf.0x" "+nan.0x"))
        (for-each
         (lambda (text) (check-fail s-file text))
         '("+12abc" ".12abc" "hello#t" "#t1" "#falseish" "#e1/0"))
        (check-ok s-atom "|+12abc|" (atom (string->symbol "+12abc") 1 1)))

      (define (test-literal-predicates)
        (for-each
         (lambda (text) (expect (number-literal? text) #t))
         '("12" "+i" "#e#x10" "3/4" "1e2-5e-1i" "+nan.0"))
        (for-each
         (lambda (text) (expect (number-literal? text) #f))
         '("" " 12" "12 " "12abc" "12)" "+item" "-inf.0x" "3i" "#e#i1" "#x#b1" "#b102"))
        (for-each
         (lambda (text) (expect (char-literal? text) #t))
         '("#\\a" "#\\x" "#\\x41" "#\\space" "#\\)" "#\\ "))
        (for-each
         (lambda (text) (expect (char-literal? text) #f))
         '("" "a" " #\\a" "#\\a " "#\\" "#\\spacebar" "#\\x110000" "#\\xd800"))
        (for-each
         (lambda (text) (expect (symbol-literal? text) #t))
         '("name" "+item" "+inf.0x" "#%-λ"))
        (for-each
         (lambda (text) (expect (symbol-literal? text) #f))
         '("" " name" "name " "abc#t" "+12abc" "+i" "+inf.0"))
        (for-each
         (lambda (predicate)
           (for-each
            (lambda (value)
              (expect
               (guard (ex ((error-object? ex) (error-object-message ex)))
                 (predicate value)
                 #f)
               "assertion failed"))
            '(42 #f name ())))
         (list number-literal? char-literal? symbol-literal?)))

      (define (test-s-char)
        (for-each
         (lambda (case) (check-ok s-char (car case) (atom (cadr case) 1 1)))
         '(("#\\a" #\a) ("#\\x" #\x) ("#\\x41" #\A)
           ("#\\alarm" #\alarm)
           ("#\\backspace" #\backspace)
           ("#\\delete" #\delete)
           ("#\\escape" #\escape)
           ("#\\newline" #\newline)
           ("#\\null" #\null)
           ("#\\return" #\return)
           ("#\\space" #\space)
           ("#\\tab" #\tab)))
        (check-ok s-char "#\\))" (atom #\) 1 1) ")")
        (check-ok s-char "#\\ ;comment" (atom #\space 1 1) ";comment")
        (check-fail s-char "#\\)x" "x")
        (check-fail s-char "#\\")
        (check-fail s-char "#\\spacebar" "bar")
        (check-fail s-char "#\\x110000" "110000")
        (check-fail s-char "#\\xd800" "d800"))

      (define (test-s-string)
        (check-ok s-string "\"\"" (atom "" 1 1))
        (check-ok s-string "\"hello \" " (atom "hello " 1 1) " ")
        (check-ok s-string "\"\\a\\b\\t\\n\\r\\\"\\\\\""
                  (atom (string #\alarm #\backspace #\tab #\newline #\return #\" #\\) 1 1))
        (check-ok s-string "\"\\x41;\"" (atom "A" 1 1))
        (check-fail s-string "\"abc" "")
        (check-fail s-string "\"\\q\"" "\\q\"")
        (check-fail s-string "\"\\x41\"" "\\x41\"")
        (check-fail s-string "\"\\xd800;\"" "\\xd800;\""))

      (define (test-s-pipe-symbol)
        (for-each
         (lambda (case)
           (check-ok s-pipe-symbol (car case) (atom (string->symbol (cadr case)) 1 1)))
         '(("||" "") ("|hello world|" "hello world") ("|12|" "12")
           ("|#t|" "#t") ("|.|" ".") ("|a\\|b|" "a|b") ("|\\x3bb;|" "λ")
           ("|a\\nb|" "a\nb") ("|a\\\\b|" "a\\b")))
        (check-ok s-pipe-symbol "|x|)" (atom 'x 1 1) ")")
        (for-each
         (lambda (text) (check-fail s-file text))
         '("|unterminated" "|\\q|" "|\\x41|" "|\\xd800;|")))

      (define (test-s-bytevector)
        (check-ok s-bytevector "#u8()" (atom #u8() 1 1))
        (check-ok s-bytevector "#U8(0 127 255)" (atom #u8(0 127 255) 1 1))
        (check-ok s-bytevector "#u8(#xFF #e1.0 #b10)" (atom #u8(255 1 2) 1 1))
        (check-ok s-bytevector "#u8[1 2]" (atom #u8(1 2) 1 1))
        (check-ok s-bytevector "#u8{1 2}" (atom #u8(1 2) 1 1))
        (check-ok s-atom "#u8(1 2) " (atom #u8(1 2) 1 1) " ")
        (check-fail s-list "#u8(1 2)")
        (check-fail s-vector "#u8(1 2)" "u8(1 2)")
        (check-ok s-bytevector "#u8(#;999 1 ; comment\n #| block |# 2))"
                  (atom #u8(1 2) 1 1) ")")
        (check-ok s-bytevector "#u8(#;999)" (atom #u8() 1 1))
        (check-ok s-expr " \n #u8(1)" (atom #u8(1) 2 2))
        (expect (syntax->datum (atom #u8(1 2) 1 1)) #u8(1 2))
        (for-each
         (lambda (text)
           (expect (parse-result-err? (s-bytevector (string->reader "bytevector.scm" text))) #t)
           (check-fail s-file text))
         '("#u8(256)" "#u8(-1)" "#u8(1.0)" "#u8(1/2)" "#u8(#t)" "#u8(x)"
           "#u8((1))" "#u8(#u8(1))" "#u8(1 . 2)" "#u8(1 . ())" "#u8(. 1)"
           "#u8(1" "#u8 (1)" "#u8[1)")))

      (define (test-s-vector)
        (check-fail s-vector "(a b)")
        (check-ok s-vector "#()" (make-vector-syntax '() (at 1 1)))
        (check-ok s-vector "#(a 12)"
                  (make-vector-syntax (list (atom 'a 1 3) (atom 12 1 5)) (at 1 1)))
        (check-ok s-vector "#(#(x))"
                  (make-vector-syntax
                   (list (make-vector-syntax (list (atom 'x 1 5)) (at 1 3))) (at 1 1)))
        (check-ok s-vector "#[(a . b) #u8(1)]"
                  (make-vector-syntax
                   (list (make-list-syntax (list (atom 'a 1 4)) (atom 'b 1 8) (at 1 3))
                         (atom #u8(1) 1 11)) (at 1 1)))
        (check-ok s-file " \n#(x)"
                  (list (make-vector-syntax (list (atom 'x 2 3)) (at 2 1))))
        (expect (syntax? (make-vector-syntax '() (at 1 1))) #t)
        (check-fail s-atom "#(1 2)")
        (for-each
         (lambda (text)
           (expect (parse-result-err? (s-vector (string->reader "vector.scm" text))) #t)
           (check-fail s-file text))
         '("#(a . b)" "#(a . ())" "#(. a)" "#(a" "# (a)" "#[a)")))

      (define (test-s-list)
        (check-fail s-list "#(a b)")
        (check-ok s-list "()" (make-list-syntax '() '() (at 1 1)))
        (check-ok s-list "( \n)" (make-list-syntax '() '() (at 1 1)))
        (check-ok s-list "(a 12 )"
                  (make-list-syntax (list (atom 'a 1 2) (atom 12 1 4)) '() (at 1 1)))
        (check-ok s-list "(a . b )"
                  (make-list-syntax (list (atom 'a 1 2)) (atom 'b 1 6) (at 1 1)))
        (check-ok s-list "(a . b)"
                  (make-list-syntax (list (atom 'a 1 2)) (atom 'b 1 6) (at 1 1)))
        (check-ok s-list "(())"
                  (make-list-syntax (list (make-list-syntax '() '() (at 1 2))) '() (at 1 1)))
        (check-ok s-list "(a . ())"
                  (make-list-syntax (list (atom 'a 1 2)) (make-list-syntax '() '() (at 1 6)) (at 1 1)))
        (check-ok s-list "[a {12}]"
                  (make-list-syntax
                   (list (atom 'a 1 2) (make-list-syntax (list (atom 12 1 5)) '() (at 1 4)))
                   '() (at 1 1)))
        (check-ok s-list "(.x ... |.| \".\")"
                  (make-list-syntax
                   (list (atom '.x 1 2) (atom '... 1 5) (atom (string->symbol ".") 1 9)
                         (atom "." 1 13))
                   '() (at 1 1)))
        (check-fail s-list "(. a)")
        (check-fail s-list "(a .)")
        (check-fail s-list "(a . b c)")
        (check-fail s-list "(a"))

      (define (test-syntax->datum)
        (let ((forms (pmap s-file (lambda (forms) (map syntax->datum forms)))))
          (check-ok forms "'#(a (b . c) #() #u8(1))"
                    '((quote #(a (b . c) #() #u8(1)))))
          (check-ok forms "(a . #(b #()))" '((a . #(b #()))))))

      (define (test-improper-tail)
        (check-ok improper-tail " . a" (atom 'a 1 4))
        (check-ok improper-tail ".\tx" (atom 'x 1 3))
        (check-ok improper-tail ".;comment\nx" (atom 'x 2 1))
        (check-ok improper-tail ". #;ignored #t" (atom #t 1 13))
        (check-ok improper-tail ".(x)"
                  (make-list-syntax (list (atom 'x 1 3)) '() (at 1 2)))
        (check-ok improper-tail ".(x . y)"
                  (make-list-syntax (list (atom 'x 1 3)) (atom 'y 1 7) (at 1 2)))
        (check-ok improper-tail ".\"x\"" (atom "x" 1 2))
        (check-ok improper-tail ".|x|" (atom 'x 1 2))
        (check-fail improper-tail "")
        (check-fail improper-tail "." "")
        (check-fail improper-tail ".5" "5")
        (check-fail improper-tail " .a" "a")
        (check-fail improper-tail " .)" ")")
        (for-each
         (lambda (text) (check-fail s-file text))
         '("(a .#t)" "(a .#(b))" "(a .#u8(1))" "(a .'b)" "(a .#|comment|# b)")))

      (define (test-s-quote)
        (for-each
         (lambda (case)
           (let ((prefix (car case)) (name (cadr case)))
             (check-ok s-quote (string-append prefix "x")
                       (make-list-syntax (list (atom name 1 1) (atom 'x 1 (+ 1 (string-length prefix))))
                                         '()
                                         (at 1 1)))))
         '(("'" quote) ("`" quasiquote) ("," unquote) (",@" unquote-splicing)))
        (check-ok s-quote "'\nx"
                  (make-list-syntax (list (atom 'quote 1 1) (atom 'x 2 1)) '() (at 1 1)))
        (check-ok s-quote "''x"
                  (make-list-syntax
                   (list (atom 'quote 1 1)
                         (make-list-syntax (list (atom 'quote 1 2) (atom 'x 1 3)) '() (at 1 2)))
                   '()
                   (at 1 1)))
        (check-fail s-quote "'" "")
        (check-fail s-quote ",@)" ")"))

      (define (test-expr-and-file)
        (check-ok s-expr " \n12 " (atom 12 2 1) " ")
        (check-ok s-atom "12 " (atom 12 1 1) " ")
        (check-fail s-atom " 12")
        (check-ok s-file "" '())
        (check-ok s-file " \n\t" '())
        (check-ok s-file "abc 12\n" (list (atom 'abc 1 1) (atom 12 1 5)))
        (for-each
         (lambda (text) (check-fail s-file text))
         '("12abc" "#b102" "#o8" "#xg" "#x1.2" "1e" "1e+" "1/" "1/2/3" "3i" "#e#i1" "#x#b1" "#trueish" "abc#t" "hello#t" "hello'world" "#\\spacebar" "\"\\q\"" "\"unterminated" "(a" ")" "." "[a)" "{a]" "(a . b . c)")))

      (define (test-s-file-result)
        (let ((result (s-file (string->reader "empty.scm" ""))))
          (expect (parse-result-ok? result) #t)
          (expect (parse-result-value result) '()))
        (let ((result (s-file (string->reader "example.scm" "\n'x "))))
          (expect (parse-result-ok? result) #t)
          (expect
           (syntax-value (parse-result-value result))
           (syntax-value
            (list (make-list-syntax
                   (list (make-atom-syntax 'quote (make-loc "example.scm" 2 1))
                         (make-atom-syntax 'x (make-loc "example.scm" 2 2)))
                   '()
                   (make-loc "example.scm" 2 1))))))
        (let ((result (s-file (string->reader "broken.scm" "("))))
          (expect (parse-result-err? result) #t)
          (expect (reader-filename (parse-result-input result)) "broken.scm")))

      (define (test-syntax-parser)
        (run-test test-shared-rule-inputs)
        (run-test test-whitespace)
        (run-test test-intertoken-space)
        (run-test test-comments)
        (run-test test-s-boolean)
        (run-test test-integers)
        (run-test test-s-number)
        (run-test test-number-failure-position)
        (run-test test-symbols)
        (run-test test-number-symbol-boundaries)
        (run-test test-literal-predicates)
        (run-test test-s-char)
        (run-test test-s-string)
        (run-test test-s-pipe-symbol)
        (run-test test-s-bytevector)
        (run-test test-s-vector)
        (run-test test-s-list)
        (run-test test-syntax->datum)
        (run-test test-improper-tail)
        (run-test test-s-quote)
        (run-test test-expr-and-file)
        (run-test test-s-file-result))
      ))))
