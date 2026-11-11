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

    (extern char-upcase "snail.core.support" "snail:text/upcase" (impl (Fn Char -> Char)))
    (extern char-downcase "snail.core.support" "snail:text/downcase" (impl (Fn Char -> Char)))
    (extern char-foldcase "snail.core.support" "snail:text/foldcase" (impl (Fn Char -> Char)))
    (extern lowercase-flag "snail.core.support" "snail:text/lowercase" (impl (Fn Char -> I32)))
    (extern uppercase-flag "snail.core.support" "snail:text/uppercase" (impl (Fn Char -> I32)))
    (extern digit-flag "snail.core.support" "snail:text/digit-value" (impl (Fn Char -> I32)))
    (extern alphabetic-flag "snail.core.support" "snail:text/alphabetic" (impl (Fn Char -> I32)))
    (extern numeric-flag "snail.core.support" "snail:text/numeric" (impl (Fn Char -> I32)))
    (extern whitespace-flag "snail.core.support" "snail:datum/whitespace" (impl (Fn Char -> I32)))

    (: char-unicode-alphabetic? (impl (Fn Char -> Bool)))
    (define (char-unicode-alphabetic? char)
      (= (alphabetic-flag char) 1))

    (: char-unicode-numeric? (impl (Fn Char -> Bool)))
    (define (char-unicode-numeric? char)
      (= (numeric-flag char) 1))

    (: char-unicode-whitespace? (impl (Fn Char -> Bool)))
    (define (char-unicode-whitespace? char)
      (= (whitespace-flag char) 1))

    (: char-lower-case? (impl (Fn Char -> Bool)))
    (define (char-lower-case? char)
      (= (lowercase-flag char) 1))

    (: char-upper-case? (impl (Fn Char -> Bool)))
    (define (char-upper-case? char)
      (= (uppercase-flag char) 1))

    ;; A decimal digit's value in any script, or nothing for anything else.
    ;; The runtime answers -1 rather than a value it could be mistaken for.
    (: char-digit-value (impl (Fn Char -> (Option I64))))
    (define (char-digit-value char)
      (let ((value (digit-flag char)))
        (if (< value 0) (None) (Some (i32->i64 value)))))

    ;; ---- Strings ----

    ;; Simple case mapping, one scalar to one scalar.
    (: string-upcase (impl (Fn String -> String)))
    (define (string-upcase text)
      (string-generate (string-length text) (lambda (index) (char-upcase (string-ref text index)))))

    (: string-downcase (impl (Fn String -> String)))
    (define (string-downcase text)
      (string-generate (string-length text)
                       (lambda (index) (char-downcase (string-ref text index)))))

    ;; Full case folding, which may expand one scalar into several, as "ß"
    ;; into "ss"; folded strings compare equal ignoring case.
    (extern fold-length "snail.core.support" "snail:text/full-fold-length" (impl (Fn Char -> I32)))
    (extern fold-scalar
            "snail.core.support"
            "snail:text/full-fold-scalar"
            (impl (Fn Char I32 -> Char)))

    (: string-foldcase (impl (Fn String -> String)))
    (define (string-foldcase text)
      (string-concatenate
       (map (lambda (char)
              (string-generate (i32->i64 (fold-length char))
                               (lambda (index) (fold-scalar char (i64->i32 index)))))
            (string->list text))))

    ))
