;; What the text of a literal stands for: a string's characters, the
;; character `#\` names, an integer token's value, and a byte of a
;; `#u8(...)`. The lexemes have found where each literal ends; these rules
;; decide what it means. Each answers the value, or the problem with the
;; text, which the reader places at the literal.
(define-library (snail compiler read literals)
  (export
   string-value
   character-value
   integer-value
   byte-value)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler read lexemes))
  (begin

    ;; ---- Strings ----

    ;; The characters that `text`, a string's text between its quotes,
    ;; stands for.
    (: string-value (impl (Fn String -> (Result String String))))
    (define (string-value text)
      (decoded-string (string->vector text) 0 (Nil)))

    ;; The characters from `index` on, after the `decoded` ones before it,
    ;; which come latest first.
    (: decoded-string (impl (Fn (Vector Char) I64 (List Char) -> (Result String String))))
    (define (decoded-string chars index decoded)
      (cond ((= index (vector-length chars)) (Ok (list->string (reverse decoded))))
            ((char=? (vector-ref chars index) #\\)
             (result-let* ((escape (escape-at chars (+ index 1))))
               (decoded-string chars (::end escape) (Cons (::value escape) decoded))))
            (else (decoded-string chars (+ index 1) (Cons (vector-ref chars index) decoded)))))

    ;; The character an escape stands for, where `index` is just after its
    ;; backslash. A string's lexeme never ends the text with a lone
    ;; backslash, but nothing after one is an unknown escape all the same.
    (: escape-at (impl (Fn (Vector Char) I64 -> (Result (Scanned Char) String))))
    (define (escape-at chars index)
      (if (= index (vector-length chars))
          (Err "unknown string escape")
          (escape-of chars index (vector-ref chars index))))

    ;; The character that the escape `\c` stands for, where `c` is at
    ;; `index`.
    (: escape-of (impl (Fn (Vector Char) I64 Char -> (Result (Scanned Char) String))))
    (define (escape-of chars index c)
      (let ((next (+ index 1)))
        (cond ((char=? c #\n) (Ok (Scanned #\newline next)))
              ((char=? c #\t) (Ok (Scanned #\tab next)))
              ((char=? c #\r) (Ok (Scanned (integer->char 13) next)))
              ((char=? c #\0) (Ok (Scanned (integer->char 0) next)))
              ((char=? c #\x) (hex-escape chars next))
              ((or (char=? c #\\) (char=? c #\") (char=? c #\|)) (Ok (Scanned c next)))
              (else (Err "unknown string escape")))))

    ;; `\x41;`: hexadecimal digits from `index` to a semicolon, which the
    ;; string must hold.
    (: hex-escape (impl (Fn (Vector Char) I64 -> (Result (Scanned Char) String))))
    (define (hex-escape chars index)
      (match (semicolon-from chars index)
        ((None) (Err invalid-hex))
        ((Some semicolon)
         (result-let* ((char (hex-char (vector->string (subvector chars index semicolon)))))
           (Ok (Scanned char (+ semicolon 1)))))))

    (: semicolon-from (impl (Fn (Vector Char) I64 -> (Option I64))))
    (define (semicolon-from chars index)
      (cond ((= index (vector-length chars)) (None))
            ((char=? (vector-ref chars index) #\;) (Some index))
            (else (semicolon-from chars (+ index 1)))))

    ;; ---- Hexadecimal ----

    (: invalid-hex String)
    (define invalid-hex "invalid hexadecimal escape")

    ;; The character whose code the hexadecimal digits of `text` spell,
    ;; which must be a Unicode scalar value.
    (: hex-char (impl (Fn String -> (Result Char String))))
    (define (hex-char text)
      (if (= (string-length text) 0)
          (Err invalid-hex)
          (hex-digits (string->list text) 0)))

    ;; `value` is the code the digits before these spell. Another digit
    ;; never makes it smaller, so once it passes the largest scalar value
    ;; the escape is invalid, and it stops there: no number of digits can
    ;; overflow it.
    (: hex-digits (impl (Fn (List Char) I64 -> (Result Char String))))
    (define (hex-digits digits value)
      (match digits
        ((Nil) (scalar-char value))
        ((Cons digit more)
         (match (hex-digit digit)
           ((None) (Err invalid-hex))
           ((Some n)
            (if (> value largest-scalar)
                (Err invalid-hex)
                (hex-digits more (+ (* value 16) n))))))))

    (: largest-scalar I64)
    (define largest-scalar 1114111)

    ;; A scalar value is a code from 0 to 10FFFF that is no surrogate, from
    ;; D800 to DFFF: only these name a character on every host.
    (: scalar-char (impl (Fn I64 -> (Result Char String))))
    (define (scalar-char code)
      (if (or (> code largest-scalar) (and (<= 55296 code) (<= code 57343)))
          (Err invalid-hex)
          (Ok (integer->char code))))

    (: hex-digit (impl (Fn Char -> (Option I64))))
    (define (hex-digit c)
      (let ((code (char->integer c)))
        (cond ((and (<= 48 code) (<= code 57)) (Some (- code 48)))
              ((and (<= 97 code) (<= code 102)) (Some (- code 87)))
              ((and (<= 65 code) (<= code 70)) (Some (- code 55)))
              (else (None)))))

    ;; ---- Characters ----

    ;; The character that `name`, the text after `#\`, names: one
    ;; character, `x` and hexadecimal digits, or a name.
    (: character-value (impl (Fn String -> (Result Char String))))
    (define (character-value name)
      (let ((size (string-length name)))
        (cond ((= size 0) (Err "expected a character after #\\"))
              ((= size 1) (Ok (string-ref name 0)))
              ((char=? (string-ref name 0) #\x) (hex-char (substring name 1 size)))
              (else (named-character name)))))

    (: named-character (impl (Fn String -> (Result Char String))))
    (define (named-character name)
      (match (assoc-ref character-names name)
        ((Some char) (Ok char))
        ((None) (Err (string-append "unknown character name " name)))))

    (: character-names (List (Pair String Char)))
    (define character-names
      (list (Pair "space" #\space)
            (Pair "newline" #\newline)
            (Pair "tab" #\tab)
            (Pair "nul" (integer->char 0))
            (Pair "null" (integer->char 0))
            (Pair "return" (integer->char 13))
            (Pair "alarm" (integer->char 7))
            (Pair "backspace" (integer->char 8))
            (Pair "delete" (integer->char 127))
            (Pair "escape" (integer->char 27))))

    ;; ---- Integers ----

    ;; The value of an integer token, which must fit in 64 bits.
    (: integer-value (impl (Fn String -> (Result I64 String))))
    (define (integer-value text)
      (match (string->i64 text)
        ((Some value) (Ok value))
        ((None) (Err (string-append "the literal " text " does not fit I64")))))

    ;; ---- Bytes ----

    (: byte-problem String)
    (define byte-problem "a byte is an integer from 0 to 255")

    ;; A byte of a `#u8(...)`: decimal digits for a value from 0 to 255.
    (: byte-value (impl (Fn String -> (Result U8 String))))
    (define (byte-value text)
      (if (= (string-length text) 0)
          (Err byte-problem)
          (byte-digits (string->list text) 0)))

    ;; `value` is the number the digits before these spell. It is checked
    ;; before each digit, so no number of digits can overflow it.
    (: byte-digits (impl (Fn (List Char) I64 -> (Result U8 String))))
    (define (byte-digits digits value)
      (match digits
        ((Nil) (if (> value 255) (Err byte-problem) (Ok (i32->u8 (i64->i32 value)))))
        ((Cons digit more)
         (if (or (> value 255) (not (char-numeric? digit)))
             (Err byte-problem)
             (byte-digits more (+ (* value 10) (digit-value digit)))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-literals)
    (import
     (snail stage0 testing))
    (begin
      (define (test-literals)
        (test-strings)
        (test-string-problems)
        (test-characters)
        (test-scalar-values)
        (test-integers)
        (test-bytes))

      (define (test-strings)
        (expect (string-value "") (Ok ""))
        (expect (string-value "plain λ") (Ok "plain λ"))
        (expect (string-value "a\\nb\\tc\\rd\\0e")
                (Ok (list->string (list #\a
                                        #\newline
                                        #\b
                                        #\tab
                                        #\c
                                        (integer->char 13)
                                        #\d
                                        (integer->char 0)
                                        #\e))))
        (expect (string-value "\\\\ \\\" \\|") (Ok "\\ \" |"))
        (expect (string-value "\\x41;\\x3bb;!") (Ok "Aλ!"))
        (expect (string-value "\\x1F600;") (Ok "😀")))

      ;; A hexadecimal escape needs a semicolon somewhere after it, and
      ;; only hexadecimal digits before that.
      (define (test-string-problems)
        (expect (string-value "a\\qb") (Err "unknown string escape"))
        (expect (string-value "\\") (Err "unknown string escape"))
        (expect (string-value "\\x41") (Err "invalid hexadecimal escape"))
        (expect (string-value "\\x;") (Err "invalid hexadecimal escape"))
        (expect (string-value "\\x4G;") (Err "invalid hexadecimal escape"))
        (expect (string-value "\\x41 ;") (Err "invalid hexadecimal escape")))

      (define (test-characters)
        (expect (character-value "a") (Ok #\a))
        (expect (character-value "x") (Ok #\x))
        (expect (character-value "(") (Ok #\())
        (expect (character-value " ") (Ok #\space))
        (expect (character-value "λ") (Ok (integer->char 955)))
        (expect (character-value "x41") (Ok #\A))
        (expect (character-value "x3BB") (Ok (integer->char 955)))
        (expect (map character-value (list "space" "newline" "tab" "nul" "null" "return"))
                (map (lambda (code) (Ok (integer->char code))) (list 32 10 9 0 0 13)))
        (expect (map character-value (list "alarm" "backspace" "delete" "escape"))
                (map (lambda (code) (Ok (integer->char code))) (list 7 8 127 27)))
        (expect (character-value "") (Err "expected a character after #\\"))
        (expect (character-value "xyz") (Err "invalid hexadecimal escape"))
        (expect (character-value "Space") (Err "unknown character name Space"))
        (expect (character-value "ab") (Err "unknown character name ab")))

      ;; A hexadecimal escape names a scalar value, from 0 to 10FFFF and no
      ;; surrogate, in strings and characters alike. Any number of leading
      ;; zeros is fine, and any number of digits past the largest value is
      ;; a problem, not an overflow.
      (define (test-scalar-values)
        (expect (string-value "\\x0;\\xD7FF;\\xE000;\\x10FFFF;")
                (Ok (list->string (map integer->char (list 0 55295 57344 1114111)))))
        (expect (string-value "\\x000000000000000000000041;") (Ok "A"))
        (expect-invalid-hex string-value
                            (list "\\xD800;" "\\xDFFF;" "\\x110000;" "\\x12345678901234567890;"))
        (expect (character-value "x10FFFF") (Ok (integer->char 1114111)))
        (expect (character-value "x0000000000000000000041") (Ok #\A))
        (expect-invalid-hex character-value
                            (list "xD800" "xDBFF" "x110000" "x1000000000000000041")))

      ;; `decode` finds each of `texts` an invalid hexadecimal escape. The
      ;; text is part of what is compared, so a failure names it.
      (define (expect-invalid-hex decode texts)
        (for-each (lambda (text)
                    (expect (Pair text (decode text))
                            (Pair text (Err "invalid hexadecimal escape"))))
                  texts))

      (define (test-integers)
        (expect (integer-value "42") (Ok 42))
        (expect (integer-value "-7") (Ok -7))
        (expect (integer-value "+7") (Ok 7))
        (expect (integer-value "9223372036854775807") (Ok 9223372036854775807))
        (expect (integer-value "-9223372036854775808") (Ok -9223372036854775808))
        (expect (integer-value "9223372036854775808")
                (Err "the literal 9223372036854775808 does not fit I64")))

      ;; Leading zeros are digits like any other; a sign is not a digit.
      (define (test-bytes)
        (expect (byte-value "0") (Ok 0))
        (expect (byte-value "255") (Ok 255))
        (expect (byte-value "007") (Ok 7))
        (expect (byte-value "256") (Err "a byte is an integer from 0 to 255"))
        (expect (byte-value "99999999999999999999999") (Err "a byte is an integer from 0 to 255"))
        (expect (byte-value "") (Err "a byte is an integer from 0 to 255"))
        (expect (byte-value "+1") (Err "a byte is an integer from 0 to 255"))
        (expect (byte-value "1a") (Err "a byte is an integer from 0 to 255"))
        (expect (byte-value "#x1") (Err "a byte is an integer from 0 to 255")))))
   (else)))
