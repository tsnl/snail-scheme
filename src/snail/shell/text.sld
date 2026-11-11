;; Unicode character properties and case mapping, from the runtime's tables.
(define-library (snail shell text)
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
   (snail core base))
  (begin

    ;; ---- Properties ----

    (extern char-upcase "snail.core.support" "snail:text/upcase" (impl (Fn Char → Char)))
    (extern char-downcase "snail.core.support" "snail:text/downcase" (impl (Fn Char → Char)))
    (extern char-foldcase "snail.core.support" "snail:text/foldcase" (impl (Fn Char → Char)))
    (extern lowercase-flag "snail.core.support" "snail:text/lowercase" (impl (Fn Char → I32)))
    (extern uppercase-flag "snail.core.support" "snail:text/uppercase" (impl (Fn Char → I32)))
    (extern digit-flag "snail.core.support" "snail:text/digit-value" (impl (Fn Char → I32)))
    (extern alphabetic-flag "snail.core.support" "snail:text/alphabetic" (impl (Fn Char → I32)))
    (extern numeric-flag "snail.core.support" "snail:text/numeric" (impl (Fn Char → I32)))
    (extern whitespace-flag "snail.core.support" "snail:datum/whitespace" (impl (Fn Char → I32)))

    (define (char-unicode-alphabetic? (char Char)) (→ Bool)
      (= (alphabetic-flag char) 1))

    (define (char-unicode-numeric? (char Char)) (→ Bool)
      (= (numeric-flag char) 1))

    (define (char-unicode-whitespace? (char Char)) (→ Bool)
      (= (whitespace-flag char) 1))

    (define (char-lower-case? (char Char)) (→ Bool)
      (= (lowercase-flag char) 1))

    (define (char-upper-case? (char Char)) (→ Bool)
      (= (uppercase-flag char) 1))

    ;; A decimal digit's value in any script, or nothing for anything else.
    ;; The runtime answers -1 rather than a value it could be mistaken for.

    (define (char-digit-value (char Char)) (→ (Option I64))
      (let ((value (digit-flag char)))
        (if (< value 0) (None) (Some (i32->i64 value)))))

    ;; ---- Strings ----

    ;; Simple case mapping, one scalar to one scalar.

    (define (string-upcase (text String)) (→ String)
      (string-generate (string-length text) (lambda (index) (char-upcase (string-ref text index)))))

    (define (string-downcase (text String)) (→ String)
      (string-generate (string-length text)
                       (lambda (index) (char-downcase (string-ref text index)))))

    ;; Full case folding, which may expand one scalar into several, as "ß"
    ;; into "ss"; folded strings compare equal ignoring case.
    (extern fold-length "snail.core.support" "snail:text/full-fold-length" (impl (Fn Char → I32)))
    (extern fold-scalar
            "snail.core.support"
            "snail:text/full-fold-scalar"
            (impl (Fn Char I32 → Char)))

    (define (string-foldcase (text String)) (→ String)
      (string-concatenate
       (map (lambda (char)
              (string-generate (i32->i64 (fold-length char))
                               (lambda (index) (fold-scalar char (i64->i32 index)))))
            (string->list text))))

    ))
