(define-library (snail-scheme test-syntax)
  (export
   test-syntax)

  (import
   (scheme base)
   (snail-scheme source)
   (snail-scheme reader)
   (only (snail-scheme parser) pmap parse-result-ok? parse-result-err?
         parse-result-value parse-result-input)
   (snail-scheme syntax)
   (snail-scheme syntax-parser)
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
      (for-each
       (lambda (case) (check-ok s-number (car case) (atom (cadr case) 1 1)))
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
      (check-ok s-number "12)" (atom 12 1 1) ")")
      (check-fail s-number "12abc" "abc")
      (check-fail s-number "#x")
      (check-fail s-number "#e1/0" "")
      (check-fail s-number ""))

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
       '("+name" ".name" "+item" "+inf.0x" "+nan.0x"))
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

    (define (test-syntax)
      (run-test test-shared-rule-inputs)
      (run-test test-whitespace)
      (run-test test-intertoken-space)
      (run-test test-comments)
      (run-test test-s-boolean)
      (run-test test-integers)
      (run-test test-s-number)
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
      (run-test test-s-file-result))))
