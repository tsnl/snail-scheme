;; Unicode character properties and case mapping, from the runtime's tables.
(define-library (lofi text)
  (export
   char-upcase
   char-downcase
   char-foldcase
   char-unicode-alphabetic?
   char-unicode-numeric?
   char-unicode-whitespace?
   char-lower-case?
   string-upcase
   string-downcase)
  (import
   (lofi base))
  (begin

    ;; ---- Properties ----

    (extern char-upcase "snail.library" "snail:text/upcase" (-> Char Char))
    (extern char-downcase "snail.library" "snail:text/downcase" (-> Char Char))
    (extern char-foldcase "snail.library" "snail:text/foldcase" (-> Char Char))
    (extern lowercase-flag "snail.library" "snail:text/lowercase" (-> Char I32))
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

    ;; ---- Strings ----

    ;; Simple case mapping, one scalar to one scalar.
    (: string-upcase (-> String String))
    (define (string-upcase text)
      (string-generate (string-length text) (lambda (index) (char-upcase (string-ref text index)))))

    (: string-downcase (-> String String))
    (define (string-downcase text)
      (string-generate (string-length text) (lambda (index) (char-downcase (string-ref text index)))))

    ))
