(define-library (snail-scheme test-syntax)
  (export
   test-syntax)

  (import
   (scheme base)
   (snail-scheme source)
   (snail-scheme reader)
   (only (snail-scheme parser) pmap)
   (snail-scheme syntax)
   (rename (snail-scheme test-utils) (check-ok check-parser-ok)))

  (begin
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

    (define (test-whitespace)
      (check-ok (whitespace) "" '())
      (check-ok (whitespace) " \t\n\ra" '() "a")
      (check-ok (whitespace) "a" '() "a")
      (check-ok (whitespace) " ; comment" '() "; comment")
      (check-ok (whitespace) "#| comment |#" '() "#| comment |#")
      (check-fail (whitespace-char) "a"))

    (define (test-intertoken-space)
      (check-ok (intertoken-space) "" '())
      (check-ok (intertoken-space) "x" '() "x")
      (check-ok (intertoken-space) " \t\n\rx" '() "x")
      (check-ok (intertoken-space) " ; line\n#| block |# #; ignored \tx" '() "x"))

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
      (check-ok (s-sequence) "(;line\n a #;b . #|tail|# c )"
                (make-list-syntax (list (atom 'a 2 2)) (atom 'c 2 19) (at 1 1)))
      (check-fail (file) "#| unfinished")
      (check-fail (file) "#;")
      (check-fail (file) "#| outer #| unfinished |#")
      (check-ok (block-comment) "#| # #| nested |# | |#x" '() "x"))

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

    (define (test-symbol-or-number)
      (for-each
       (lambda (case) (check-ok (symbol-or-number) (car case) (atom (cadr case) 1 1)))
       '(("0" 0) ("123" 123) ("-12" -12) ("#xFF" 255)
         ("#b101" 5)
         ("#o17" 15)
         ("#d12" 12)
         ("3/4" 3/4)
         ("1.25" 1.25)
         ("2e3" 2000.0)
         ("#e1.25" 5/4)
         ("1+2i" 1+2i)
         ("#E#Xf/f" 1) ("#x#e10" 16) ("#e#d1.25" 5/4)
         ("#i#b10" 2.0) ("#D#I12" 12.0) ("#O17" 15)
         (".5" 0.5) ("1." 1.0) ("-1.25E-2" -0.0125)
         ("+i" +i) ("-i" -i) ("+2i" +2i) ("2-i" 2-i)
         ("1/2+3/4i" 1/2+3/4i) ("1e2-5e-1i" 100.0-0.5i)
         ("+inf.0" +inf.0) ("-inf.0" -inf.0) ("2@0" 2)))
      (check-ok (symbol-or-number) "12)" (atom 12 1 1) ")")
      (check-fail (symbol-or-number) "12abc" "")
      (check-fail (symbol-or-number) "#x" "")
      (check-fail (symbol-or-number) "#e1/0" "")
      (check-fail (symbol-or-number) ""))

    (define (test-symbols)
      (for-each
       (lambda (name) (check-ok (symbol-or-number) name (atom (string->symbol name) 1 1)))
       '("hello?" "a.b" "+" "-" "..." "+.x" ".x" "+item" "-inf.0x" "+@x" "-.." "λ"))
      (check-ok (symbol-or-number) "abc\t" (atom 'abc 1 1) "\t")
      (check-ok (symbol-or-number) "abc\n" (atom 'abc 1 1) "\n")
      (check-fail (symbol-or-number) "12abc" "")
      (check-fail (symbol-or-number) "abc#t" "")
      (check-fail (symbol-or-number) "." "")
      (check-fail (symbol-or-number) "\"unterminated"))

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
       '("" "a" " #\\a" "#\\a " "#\\" "#\\spacebar" "#\\x110000" "#\\xd800")))

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
      (check-fail (char-expr) "#\\" "")
      (check-fail (char-expr) "#\\spacebar" "")
      (check-fail (char-expr) "#\\x110000" "")
      (check-fail (char-expr) "#\\xd800" ""))

    (define (test-s-string-terminal)
      (check-ok (s-string-terminal) "\"\"" (atom "" 1 1))
      (check-ok (s-string-terminal) "\"hello \" " (atom "hello " 1 1) " ")
      (check-ok (s-string-terminal) "\"\\a\\b\\t\\n\\r\\\"\\\\\""
                (atom (string #\alarm #\backspace #\tab #\newline #\return #\" #\\) 1 1))
      (check-ok (s-string-terminal) "\"\\x41;\"" (atom "A" 1 1))
      (check-fail (s-string-terminal) "\"abc" "")
      (check-fail (s-string-terminal) "\"\\q\"" "\\q\"")
      (check-fail (s-string-terminal) "\"\\x41\"" "\\x41\"")
      (check-fail (s-string-terminal) "\"\\xd800;\"" "\\xd800;\""))

    (define (test-s-pipe-symbol-terminal)
      (for-each
       (lambda (case)
         (check-ok (s-pipe-symbol-terminal) (car case) (atom (string->symbol (cadr case)) 1 1)))
       '(("||" "") ("|hello world|" "hello world") ("|12|" "12")
         ("|#t|" "#t") ("|.|" ".") ("|a\\|b|" "a|b") ("|\\x3bb;|" "λ")
         ("|a\\nb|" "a\nb") ("|a\\\\b|" "a\\b")))
      (check-ok (s-pipe-symbol-terminal) "|x|)" (atom 'x 1 1) ")")
      (for-each
       (lambda (text) (check-fail (file) text))
       '("|unterminated" "|\\q|" "|\\x41|" "|\\xd800;|")))

    (define (test-bytevector-sequences)
      (check-ok (s-sequence) "#u8()" (atom (bytevector) 1 1))
      (check-ok (s-sequence) "#U8(0 127 255)" (atom (bytevector 0 127 255) 1 1))
      (check-ok (s-sequence) "#u8(#xFF #e1.0 #b10)" (atom (bytevector 255 1 2) 1 1))
      (check-ok (s-sequence) "#u8[1 2]" (atom (bytevector 1 2) 1 1))
      (check-fail (s-terminal) "#u8(1 2)")
      (check-ok (s-sequence) "#u8(#;999 1 ; comment\n #| block |# 2))"
                (atom (bytevector 1 2) 1 1) ")")
      (for-each
       (lambda (text) (check-fail (file) text))
       '("#u8(256)" "#u8(-1)" "#u8(1.0)" "#u8(1/2)" "#u8(#t)" "#u8(x)"
         "#u8((1))" "#u8(1 . 2)" "#u8(1 . ())" "#u8(. 1)" "#u8(1" "#u8 (1)" "#u8[1)")))

    (define (test-vector-sequences)
      (check-ok (s-sequence) "#()" (make-vector-syntax '() (at 1 1)))
      (check-ok (s-sequence) "#(a 12)"
                (make-vector-syntax (list (atom 'a 1 3) (atom 12 1 5)) (at 1 1)))
      (check-ok (s-sequence) "#(#(x))"
                (make-vector-syntax
                 (list (make-vector-syntax (list (atom 'x 1 5)) (at 1 3))) (at 1 1)))
      (check-ok (s-sequence) "#[(a . b) #u8(1)]"
                (make-vector-syntax
                 (list (make-list-syntax (list (atom 'a 1 4)) (atom 'b 1 8) (at 1 3))
                       (atom (bytevector 1) 1 11)) (at 1 1)))
      (check-ok (file) " \n#(x)"
                (list (make-vector-syntax (list (atom 'x 2 3)) (at 2 1))))
      (expect (syntax? (make-vector-syntax '() (at 1 1))) #t)
      (check-fail (s-terminal) "#(1 2)")
      (for-each
       (lambda (text) (check-fail (file) text))
       '("#(a . b)" "#(a . ())" "#(. a)" "#(a" "# (a)" "#[a)")))

    (define (test-list-sequences)
      (check-ok (s-sequence) "()" (make-list-syntax '() '() (at 1 1)))
      (check-ok (s-sequence) "( \n)" (make-list-syntax '() '() (at 1 1)))
      (check-ok (s-sequence) "(a 12 )"
                (make-list-syntax (list (atom 'a 1 2) (atom 12 1 4)) '() (at 1 1)))
      (check-ok (s-sequence) "(a . b )"
                (make-list-syntax (list (atom 'a 1 2)) (atom 'b 1 6) (at 1 1)))
      (check-ok (s-sequence) "(())"
                (make-list-syntax (list (make-list-syntax '() '() (at 1 2))) '() (at 1 1)))
      (check-ok (s-sequence) "(a . ())"
                (make-list-syntax (list (atom 'a 1 2)) (make-list-syntax '() '() (at 1 6)) (at 1 1)))
      (check-ok (s-sequence) "[a {12}]"
                (make-list-syntax
                 (list (atom 'a 1 2) (make-list-syntax (list (atom 12 1 5)) '() (at 1 4)))
                 '() (at 1 1)))
      (check-ok (s-sequence) "(.x ... |.| \".\")"
                (make-list-syntax
                 (list (atom '.x 1 2) (atom '... 1 5) (atom (string->symbol ".") 1 9)
                       (atom "." 1 13))
                 '() (at 1 1)))
      (check-fail (s-sequence) "(. a)")
      (check-fail (s-sequence) "(a .)")
      (check-fail (s-sequence) "(a . b c)")
      (check-fail (s-sequence) "(a"))

    (define (test-improper-tail)
      (check-ok (improper-tail) " . a" (atom 'a 1 4))
      (check-ok (improper-tail) ".\tx" (atom 'x 1 3))
      (check-ok (improper-tail) ".;comment\nx" (atom 'x 2 1))
      (check-ok (improper-tail) ". #;ignored #t" (atom #t 1 13))
      (check-ok (improper-tail) ".(x)"
                (make-list-syntax (list (atom 'x 1 3)) '() (at 1 2)))
      (check-ok (improper-tail) ".(x . y)"
                (make-list-syntax (list (atom 'x 1 3)) (atom 'y 1 7) (at 1 2)))
      (check-ok (improper-tail) ".\"x\"" (atom "x" 1 2))
      (check-ok (improper-tail) ".|x|" (atom 'x 1 2))
      (check-fail (improper-tail) "")
      (check-fail (improper-tail) " .a" "a")
      (check-fail (improper-tail) " .)" ")")
      (for-each
       (lambda (text) (check-fail (file) text))
       '("(a .#t)" "(a .#(b))" "(a .#u8(1))" "(a .'b)" "(a .#|comment|# b)")))

    (define (test-s-quote)
      (for-each
       (lambda (case)
         (let ((prefix (car case)) (name (cadr case)))
           (check-ok (s-quote) (string-append prefix "x")
                     (make-list-syntax (list (atom name 1 1) (atom 'x 1 (+ 1 (string-length prefix))))
                                       '()
                                       (at 1 1)))))
       '(("'" quote) ("`" quasiquote) ("," unquote) (",@" unquote-splicing)))
      (check-ok (s-quote) "'\nx"
                (make-list-syntax (list (atom 'quote 1 1) (atom 'x 2 1)) '() (at 1 1)))
      (check-ok (s-quote) "''x"
                (make-list-syntax
                 (list (atom 'quote 1 1)
                       (make-list-syntax (list (atom 'quote 1 2) (atom 'x 1 3)) '() (at 1 2)))
                 '()
                 (at 1 1)))
      (check-fail (s-quote) "'" "")
      (check-fail (s-quote) ",@)" ")"))

    (define (test-expr-and-file)
      (check-ok (expr) " \n12 " (atom 12 2 1) " ")
      (check-ok (s-terminal) "12 " (atom 12 1 1) " ")
      (check-fail (s-terminal) " 12")
      (check-ok (file) "" '())
      (check-ok (file) " \n\t" '())
      (check-ok (file) "abc 12\n" (list (atom 'abc 1 1) (atom 12 1 5)))
      (for-each
       (lambda (text) (check-fail (file) text))
       '("12abc" "#b102" "#o8" "#xg" "#x1.2" "1e" "1e+" "1/" "1/2/3" "3i" "#e#i1" "#x#b1" "#trueish" "abc#t" "hello#t" "hello'world" "#\\spacebar" "\"\\q\"" "\"unterminated" "(a" ")" "." "[a)" "{a]" "(a . b . c)")))

    (define (test-parse-file)
      (expect (parse-file (string->reader "empty.scm" "")) '())
      (expect
       (syntax-value (parse-file (string->reader "example.scm" "\n'x ")))
       (syntax-value
        (list (make-list-syntax
               (list (make-atom-syntax 'quote (make-loc "example.scm" 2 1))
                     (make-atom-syntax 'x (make-loc "example.scm" 2 2)))
               '()
               (make-loc "example.scm" 2 1)))))
      (expect
       (guard (ex ((and (error-object? ex) (equal? (error-object-message ex) "parse failed"))
                   (car (error-object-irritants ex))))
         (parse-file (string->reader "broken.scm" "(")))
       "broken.scm"))

    (define (test-syntax)
      (run-test test-whitespace)
      (run-test test-intertoken-space)
      (run-test test-comments)
      (run-test test-boolean-expr)
      (run-test test-integers)
      (run-test test-symbol-or-number)
      (run-test test-symbols)
      (run-test test-literal-predicates)
      (run-test test-char-expr)
      (run-test test-s-string-terminal)
      (run-test test-s-pipe-symbol-terminal)
      (run-test test-bytevector-sequences)
      (run-test test-vector-sequences)
      (run-test test-list-sequences)
      (run-test test-improper-tail)
      (run-test test-s-quote)
      (run-test test-expr-and-file)
      (run-test test-parse-file))))
