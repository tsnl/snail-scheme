; Helpers stay in the parser library so tests can exercise private parsers.
; Compare record fields explicitly: R7RS does not require structural equal?
; for records. Syntax comparisons include every node's source location.

(define (test-value value)
  (cond
    ((atom-syntax? value)
      (list 'atom (atom-syntax-value value) (test-value (syntax-loc value))))
    ((list-syntax? value)
      (list 'list
        (test-value (list-syntax-elements value))
        (test-value (list-syntax-improper-tail value))
        (test-value (syntax-loc value))))
    ((loc? value)
      (list (loc-filename value) (loc-line value) (loc-column value)))
    ((pair? value) (cons (test-value (car value)) (test-value (cdr value))))
    (else value)))

(define (at line column)
  (make-loc "<anonymous-input-stream>" line column))

(define (atom value line column)
  (make-atom-syntax value (at line column)))

; Success defaults to consuming all input; failure defaults to consuming none.
; Supply a remainder to check prefix parsers and failures after partial progress.
(define (check-ok parser text value . remainder)
  (let ((result (parser (string->input-stream text))))
    (expect
      (list text (parse-result-ok? result) (test-value (parse-result-value result))
        (list->string (input-stream-chars (parse-result-input result))))
      (list text #t (test-value value) (if (null? remainder) "" (car remainder))))))

(define (check-fail parser text . remainder)
  (let ((result (parser (string->input-stream text))))
    (expect
      (list text (parse-result-err? result) (parse-result-value result)
        (list->string (input-stream-chars (parse-result-input result))))
      (list text #t '() (if (null? remainder) text (car remainder))))))

;
; Input stream and parser combinators
;

(define (test-input-stream)
  (let* ((a (string->input-stream "a\nb"))
         (newline (next-input-stream a))
         (b (next-input-stream newline))
         (end (next-input-stream b)))
    (expect (list-map peek-input-stream (list a newline b end)) '(#\a #\newline #\b ()))
    (expect (list-map (lambda (input) (test-value (input-stream-loc input)))
             (list a newline b end))
      (test-value (list (at 1 1) (at 1 2) (at 2 1) (at 2 2))))
    (expect (input-stream-eof? a) #f)
    (expect (input-stream-eof? end) #t))
  (for-each
    (lambda (text)
      (check-ok (chain (lambda (_) (whitespace)) (lambda (_) (location)))
        text
        (at 2 1)))
    '("\n" "\r" "\r\n")))

(define (test-return-and-fail)
  (check-ok (return #f) "a" #f "a")
  (check-ok (return '()) "" '())
  (check-fail (fail) "a"))

(define (test->>=)
  (check-ok (>>= (char #\a) (lambda (value) (return (string value)))) "ab" "a" "b")
  (check-ok (>>= (char #\a) (lambda (value) (char value))) "aa" #\a)
  (check-fail (>>= (fail) (lambda (_) (error "binder must not run"))) "a")
  (check-fail (>>= (char #\a) (lambda (_) (fail))) "ab" "b"))

(define (test-chain)
  (check-ok (chain) "a" '() "a")
  (check-ok (chain (lambda (_) (char #\a)) (lambda (_) (char #\b))) "ab" #\b)
  (check-fail (chain (lambda (_) (char #\a)) (lambda (_) (char #\b))) "ac" "c"))

(define (test-map)
  (check-ok (map (char #\a) string) "ab" "a" "b")
  (check-ok (map (return #f) not) "a" #t "a")
  (check-ok (map (tuple (char #\a) (char #\b)) list->string) "ab" "ab")
  (check-fail (map (tag "ab") (lambda (_) (error "transform must not run"))) "ac" "c"))

(define (test-char-if)
  (check-ok (char-if char-alphabetic?) "ab" #\a "b")
  (check-fail (char-if char-alphabetic?) "1")
  (check-fail (char-if (lambda (_) (error "predicate must not run at EOF"))) "")
  (check-ok (char-from '(#\a #\b)) "b" #\b)
  (check-fail (char-from '()) "a"))

(define (test-repeat)
  (check-ok (repeat (char #\a)) "aaab" '(#\a #\a #\a) "b")
  (check-ok (repeat (char #\a)) "b" '() "b")
  (check-ok (repeat (char #\a)) "" '())
  (check-ok (repeat (tag "ab")) "abac" '("ab") "ac")
  (for-each
    (lambda (parser)
      (expect
        (guard (ex ((error-object? ex) (error-object-message ex)))
          ((repeat parser) (string->input-stream "")))
        "repeat: parser succeeded without consuming input"))
    (list (return '()) (optional (char #\a)) (eof))))

(define (test-repeat-at-least-once)
  (check-ok (repeat-at-least-once (char #\a)) "a" '(#\a))
  (check-ok (repeat-at-least-once (char #\a)) "aab" '(#\a #\a) "b")
  (check-ok (repeat-at-least-once (discard (char #\a))) "aa" '(() ()))
  (check-fail (repeat-at-least-once (char #\a)) "b")
  (check-fail (repeat-at-least-once (char #\a)) ""))

(define (test-choice)
  (check-ok (choice (tag "ab") (tag "ac")) "ac" "ac")
  (check-ok (choice (tag "a") (tag "ab")) "ab" "a" "b")
  (check-fail (choice (tag "ab") (tag "ac")) "ad")
  (check-fail (choice) "a"))

(define (test-discard)
  (check-ok (discard (char #\a)) "ab" '() "b")
  (check-fail (discard (char #\a)) "b"))

(define (test-tuple)
  (check-ok (tuple) "a" '() "a")
  (check-ok (tuple (char #\a) (char #\b) (char #\c)) "abc" '(#\a #\b #\c))
  (check-fail (tuple (char #\a) (char #\b)) "ac" "c"))

(define (test-optional)
  (check-ok (optional (char #\a)) "ab" #\a "b")
  (check-ok (optional (tag "ab")) "ac" '() "ac")
  (check-ok (optional (char #\a)) "" '()))

(define (test-tag)
  (check-ok (tag "ab") "abc" "ab" "c")
  (check-ok (tag "") "a" "" "a")
  (check-ok (tag-val "a" #f) "a" #f)
  (check-fail (tag "ab") "ac" "c")
  (check-fail (tag "a") ""))

(define (test-eof-and-location)
  (check-ok (eof) "" '())
  (check-fail (eof) "a")
  (check-ok (location) "a" (at 1 1) "a")
  (check-ok (chain (lambda (_) (tag "a\n")) (lambda (_) (location))) "a\nb" (at 2 1) "b"))

;
; Language parsers
;

(define (test-whitespace)
  (check-ok (whitespace) "" '())
  (check-ok (whitespace) " \t\n\ra" '() "a")
  (check-ok (whitespace) "a" '() "a")
  (check-fail (whitespace-char) "a"))

(define (test-comments)
  (check-ok (line-comment) "; comment\nx" '() "\nx")
  (check-ok (line-comment) "; comment" '())
  (check-fail (line-comment) "x")
  (check-ok (block-comment) "#| outer #| inner |# end |#x" '() "x")
  (check-ok (block-comment) "#||#" '())
  (check-fail (block-comment) "#| unfinished" "")
  (check-ok (datum-comment) "#;(a . b)x" '() "x")
  (check-ok (datum-comment) "#;#;a b c" '() " c")
  (check-fail (datum-comment) "#;" "")
  (check-ok (file) "; line\n#| block |# #; ignored " '())
  (check-ok (file) "; line\n#;#t x" (list (atom 'x 2 6)))
  (check-ok (list-expr) "(;line\n a #;b . #|tail|# c )"
    (make-list-syntax (list (atom 'a 2 2)) (atom 'c 2 19) (at 1 1)))
  (check-fail (file) "#| unfinished")
  (check-fail (file) "#;"))

(define (test-token)
  (check-ok (token) "hello)" "hello" ")")
  (check-fail (token) "")
  (check-fail (token) "(")
  (check-ok (token-end) ";" '() ";")
  (check-ok (token-end) "" '())
  (check-fail (token-end) "a"))

(define (test-boolean-expr)
  (check-ok (boolean-expr) "#t" (atom #t 1 1))
  (check-ok (boolean-expr) "#FALSE" (atom #f 1 1))
  (check-ok (boolean-expr) "#True)" (atom #t 1 1) ")")
  (check-fail (boolean-expr) "#trueish" "")
  (check-fail (boolean-expr) ""))

(define (test-integers)
  (check-ok (decimal-digit) "9a" #\9 "a")
  (check-fail (decimal-digit) "a")
  (check-ok (hexadecimal-digit) "Fz" #\F "z")
  (check-fail (hexadecimal-digit) "g")
  (check-ok (decimal-integer) "123a" 123 "a")
  (check-ok (hexadecimal-integer) "aFz" 175 "z")
  (check-fail (decimal-integer) "")
  (check-fail (hexadecimal-integer) "g"))

(define (test-number-expr)
  (for-each
    (lambda (case) (check-ok (number-expr) (car case) (atom (cadr case) 1 1)))
    '(("0" 0) ("123" 123) ("-12" -12) ("#xFF" 255)
      ("#b101" 5)
      ("#o17" 15)
      ("#d12" 12)
      ("3/4" 3/4)
      ("1.25" 1.25)
      ("2e3" 2000.0)
      ("#e1.25" 5/4)
      ("1+2i" 1+2i)))
  (check-ok (number-expr) "12)" (atom 12 1 1) ")")
  (check-fail (number-expr) "12abc" "")
  (check-fail (number-expr) "#x" "")
  (check-fail (number-expr) ""))

(define (test-identifier-expr)
  (for-each
    (lambda (name) (check-ok (identifier-expr) name (atom (string->symbol name) 1 1)))
    '("hello?" "a.b" "+" "-" "..." "+.x" ".x"))
  (check-ok (identifier-expr) "abc\t" (atom 'abc 1 1) "\t")
  (check-ok (identifier-expr) "abc\n" (atom 'abc 1 1) "\n")
  (check-fail (identifier-expr) "12abc" "")
  (check-fail (identifier-expr) "+i" "")
  (check-fail (identifier-expr) "." "")
  (check-fail (identifier-expr) "\"unterminated"))

(define (test-char-expr)
  (for-each
    (lambda (case) (check-ok (char-expr) (car case) (atom (cadr case) 1 1)))
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
  (check-ok (char-expr) "#\\))" (atom #\) 1 1) ")")
  (check-fail (char-expr) "#\\")
  (check-fail (char-expr) "#\\spacebar" "bar")
  (check-fail (char-expr) "#\\x110000" "110000")
  (check-fail (char-expr) "#\\xd800" "d800"))

(define (test-string-expr)
  (check-ok (string-expr) "\"\"" (atom "" 1 1))
  (check-ok (string-expr) "\"hello \" " (atom "hello " 1 1) " ")
  (check-ok (string-expr) "\"\\a\\b\\t\\n\\r\\\"\\\\\""
    (atom (string #\alarm #\backspace #\tab #\newline #\return #\" #\\) 1 1))
  (check-ok (string-expr) "\"\\x41;\"" (atom "A" 1 1))
  (check-ok (string-expr-element) "\\x41;z" #\A "z")
  (check-fail (string-expr-element) "\\q")
  (check-fail (string-expr) "\"abc" "")
  (check-fail (string-expr) "\"\\q\"" "\\q\"")
  (check-fail (string-expr) "\"\\x41\"" "\\x41\"")
  (check-fail (string-expr) "\"\\xd800;\"" "\\xd800;\""))

(define (test-list-expr)
  (check-ok (list-expr) "()" (make-list-syntax '() '() (at 1 1)))
  (check-ok (list-expr) "( \n)" (make-list-syntax '() '() (at 1 1)))
  (check-ok (list-expr) "(a 12 )"
    (make-list-syntax (list (atom 'a 1 2) (atom 12 1 4)) '() (at 1 1)))
  (check-ok (list-expr) "(a . b )"
    (make-list-syntax (list (atom 'a 1 2)) (atom 'b 1 6) (at 1 1)))
  (check-ok (list-expr) "(())"
    (make-list-syntax (list (make-list-syntax '() '() (at 1 2))) '() (at 1 1)))
  (check-ok (list-expr) "(a . ())"
    (make-list-syntax (list (atom 'a 1 2)) (make-list-syntax '() '() (at 1 6)) (at 1 1)))
  (check-fail (list-expr) "(. a)" "")
  (check-fail (list-expr) "(a .)" ".)")
  (check-fail (list-expr) "(a . b c)" "c)")
  (check-fail (list-expr) "(a" ""))

(define (test-fenders-and-tail)
  (check-ok (left-fender) "(a" '() "a")
  (check-ok (right-fender) ")a" '() "a")
  (check-fail (left-fender) ")")
  (check-fail (right-fender) "")
  (check-ok (improper-tail) " . a" (atom 'a 1 4))
  (check-ok (improper-tail) " .a" '() " .a")
  (check-ok (improper-tail) " .)" '() " .)"))

(define (test-quote-expr)
  (for-each
    (lambda (case)
      (let ((prefix (car case)) (name (cadr case)))
        (check-ok (quote-expr) (string-append prefix "x")
          (make-list-syntax (list (atom name 1 1) (atom 'x 1 (+ 1 (string-length prefix))))
            '()
            (at 1 1)))))
    '(("'" quote) ("`" quasiquote) ("," unquote) (",@" unquote-splicing)))
  (check-ok (quote-expr) "'\nx"
    (make-list-syntax (list (atom 'quote 1 1) (atom 'x 2 1)) '() (at 1 1)))
  (check-ok (quote-expr) "''x"
    (make-list-syntax
      (list (atom 'quote 1 1)
        (make-list-syntax (list (atom 'quote 1 2) (atom 'x 1 3)) '() (at 1 2)))
      '()
      (at 1 1)))
  (check-fail (quote-expr) "'" "")
  (check-fail (quote-expr) ",@)" ")"))

(define (test-expr-and-file)
  (check-ok (expr) " \n12 " (atom 12 2 1) " ")
  (check-ok (file) "" '())
  (check-ok (file) " \n\t" '())
  (check-ok (file) "abc 12\n" (list (atom 'abc 1 1) (atom 12 1 5)))
  (for-each
    (lambda (text) (check-fail (file) text))
    '("12abc" "#\\spacebar" "\"\\q\"" "\"unterminated" "(a" ")" ".")))

(define (test-parse-file)
  (expect
    (test-value (parse-file "example.scm" "\n'x "))
    (test-value
      (list (make-list-syntax
             (list (make-atom-syntax 'quote (make-loc "example.scm" 2 1))
               (make-atom-syntax 'x (make-loc "example.scm" 2 2)))
             '()
             (make-loc "example.scm" 2 1)))))
  (expect
    (guard (ex ((and (error-object? ex) (equal? (error-object-message ex) "parse failed"))
                (car (error-object-irritants ex))))
      (parse-file "broken.scm" "("))
    "broken.scm"))

(define (test-parser)
  (run-test test-input-stream)
  (run-test test-return-and-fail)
  (run-test test->>=)
  (run-test test-chain)
  (run-test test-map)
  (run-test test-char-if)
  (run-test test-repeat)
  (run-test test-repeat-at-least-once)
  (run-test test-choice)
  (run-test test-discard)
  (run-test test-tuple)
  (run-test test-optional)
  (run-test test-tag)
  (run-test test-eof-and-location)
  (run-test test-whitespace)
  (run-test test-comments)
  (run-test test-token)
  (run-test test-boolean-expr)
  (run-test test-integers)
  (run-test test-number-expr)
  (run-test test-identifier-expr)
  (run-test test-char-expr)
  (run-test test-string-expr)
  (run-test test-list-expr)
  (run-test test-fenders-and-tail)
  (run-test test-quote-expr)
  (run-test test-expr-and-file)
  (run-test test-parse-file))
