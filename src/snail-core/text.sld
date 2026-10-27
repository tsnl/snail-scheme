;; Unicode character properties and case mapping, from the runtime's tables.
(define-library (snail-core text)
  (export
   char-upcase
   char-downcase
   char-foldcase
   char-unicode-alphabetic?
   char-unicode-numeric?
   char-unicode-whitespace?
   char-lower-case?
   char-upper-case?
   char-digit-value
   string-upcase
   string-downcase
   string-foldcase)
  (import
   (snail-core base))
  (begin

    ;; ---- Properties ----

    (extern char-upcase "snail.library" "snail:text/upcase" (-> Char Char))
    (extern char-downcase "snail.library" "snail:text/downcase" (-> Char Char))
    (extern char-foldcase "snail.library" "snail:text/foldcase" (-> Char Char))
    (extern lowercase-flag "snail.library" "snail:text/lowercase" (-> Char I32))
    (extern uppercase-flag "snail.library" "snail:text/uppercase" (-> Char I32))
    (extern digit-flag "snail.library" "snail:text/digit-value" (-> Char I32))
    (extern alphabetic-flag "snail.library" "snail:text/alphabetic" (-> Char I32))
    (extern numeric-flag "snail.library" "snail:text/numeric" (-> Char I32))
    (extern whitespace-flag "snail.library" "snail:datum/whitespace" (-> Char I32))

    (: char-unicode-alphabetic? (-> Char Bool))
    (define (char-unicode-alphabetic? char)
      (= (alphabetic-flag char) 1))

    (: char-unicode-numeric? (-> Char Bool))
    (define (char-unicode-numeric? char)
      (= (numeric-flag char) 1))

    (: char-unicode-whitespace? (-> Char Bool))
    (define (char-unicode-whitespace? char)
      (= (whitespace-flag char) 1))

    (: char-lower-case? (-> Char Bool))
    (define (char-lower-case? char)
      (= (lowercase-flag char) 1))

    (: char-upper-case? (-> Char Bool))
    (define (char-upper-case? char)
      (= (uppercase-flag char) 1))

    ;; A decimal digit's value in any script, or nothing for anything else.
    ;; The runtime answers -1 rather than a value it could be mistaken for.
    (: char-digit-value (-> Char (Option I64)))
    (define (char-digit-value char)
      (let ((value (digit-flag char)))
        (if (< value 0) (None) (Some (i32->i64 value)))))

    ;; ---- Strings ----

    ;; Simple case mapping, one scalar to one scalar.
    (: string-upcase (-> String String))
    (define (string-upcase text)
      (string-generate (string-length text) (lambda (index) (char-upcase (string-ref text index)))))

    (: string-downcase (-> String String))
    (define (string-downcase text)
      (string-generate (string-length text) (lambda (index) (char-downcase (string-ref text index)))))

    ;; Full case folding, which may expand one scalar into several, as "ß"
    ;; into "ss"; folded strings compare equal ignoring case.
    (extern fold-length "snail.library" "snail:text/full-fold-length" (-> Char I32))
    (extern fold-scalar "snail.library" "snail:text/full-fold-scalar" (-> Char I32 Char))

    (: string-foldcase (-> String String))
    (define (string-foldcase text)
      (string-concatenate
       (map (lambda (char)
              (string-generate (i32->i64 (fold-length char)) (lambda (index) (fold-scalar char (i64->i32 index)))))
            (string->list text))))

    ))
